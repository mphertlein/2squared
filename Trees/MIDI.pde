DiscreteParameter focusedChannel = new DiscreteParameter("CHNL", 9); 

public class MidiEngine {
  public MidiEngine() {
    for (MidiInputDevice mid : RWMidi.getInputDevices()) {
      if (mid.getName().contains("APC40")) {
        new APC40Input(mid);
      }
    }
  }
}

public class APC40Input {
  public APC40Input(MidiInputDevice device) {
    device.createInput(this);
  }
  
  public void controllerChangeReceived(rwmidi.Controller controller) {
    int cc = controller.getCC();
    int channel = controller.getChannel();
    int value = controller.getValue();
    float normalized = value / 127.;
    switch (cc) {
    case 7:
      if (channel < 8) {
        lx.engine.getDeck(channel).getFader().setNormalized(normalized);
      }
      break;
    case 14:
      output.brightness.setNormalized(normalized);
      break;
    case 16:
    case 17:
    case 18:
    case 19:
    case 20:
    case 21:
    case 22:
    case 23:
      focusedChannel.setValue(channel);
      if (channel < 8) {
        int paramNum = cc - 16;
        int pi = 0;
        for (LXParameter parameter : lx.engine.getDeck(channel).getActivePattern().getParameters()) {
          if (parameter instanceof LXNormalizedParameter) {
            if (pi == paramNum) {
              ((LXNormalizedParameter) parameter).setNormalized(normalized);
              break;
            }
            ++pi;
          }
        }
      }
      break;
      
    case 47:
      uiDeck.knob(value);
      break;
    
    default:
      println("cc:" + cc);
    }
  }
  
  public void noteOnReceived(Note note) {
    int channel = note.getChannel();
    int number = note.getPitch();
    switch (number) {
      case 91:
        uiDeck.select();
        break;
      case 94:
        uiDeck.scroll(-1);
        break;
      case 95:
        uiDeck.scroll(1);
        break;
      case 96:
        focusedChannel.increment();
        break;
      case 97:
        focusedChannel.decrement();
        break;
      default:
        println("noteOn: " + note);
        break;
    }
  }
  
  public void noteOffReceived(Note note) {
    int channel = note.getChannel();
    int number = note.getPitch();
    switch (number) {
      case 91:
      case 94:
      case 95:
      case 96:
      case 97:
        break;
      default:
        println("noteOff: " + note);
    }
  }
  
}

class UIChannelFaders extends UIContext {
  
  final static int WIDTH = 4 + 44*8;
  final static int HEIGHT = 88;
  
  UIChannelFaders(final UI ui) {
    super(ui, Trees.this.width/2-WIDTH/2, Trees.this.height-HEIGHT-4, WIDTH, HEIGHT);
    setBackgroundColor(#292929);
    setBorderColor(#444444);
    int di = 0;
    final UISlider[] sliders = new UISlider[8];
    for (final LXDeck deck : lx.engine.getDecks()) {
      sliders[deck.index] = new UISlider(UISlider.Direction.VERTICAL, 4 + deck.index*44, 4, 40, this.height - 8) {
        public void onFocus() {
          focusedChannel.setValue(deck.index);
        }
      };
      sliders[deck.index]
      .setParameter(deck.getFader())
      .addToContainer(this);
    }
    LXParameterListener listener;
    focusedChannel.addListener(listener = new LXParameterListener() {
      public void onParameterChanged(LXParameter parameter) {
        for (int i = 0; i < sliders.length; ++i) {
          sliders[i].setBackgroundColor((i == focusedChannel.getValuei()) ? ui.getHighlightColor() : #333333);
        }
      }
    });
    listener.onParameterChanged(focusedChannel);
  }
}

public class UIMultiDeck extends UIWindow {

  private final static int NUM_KNOBS = 8;
  private final static int KNOBS_PER_ROW = 4;
  
  public final static int DEFAULT_WIDTH = 140;
  public final static int DEFAULT_HEIGHT = 274;

  final UIItemList[] patternLists;
  final UIKnob[] knobs;

  public UIMultiDeck(UI ui) {
    super(ui, "DECK", Trees.this.width - 4 - DEFAULT_WIDTH, Trees.this.height - 4 - DEFAULT_HEIGHT, DEFAULT_WIDTH, DEFAULT_HEIGHT);
    int yp = TITLE_LABEL_HEIGHT;

    patternLists = new UIItemList[lx.engine.getDecks().size()];
    for (LXDeck deck : lx.engine.getDecks()) {
      List<UIItemList.Item> items = new ArrayList<UIItemList.Item>();
      for (LXPattern p : deck.getPatterns()) {
        items.add(new PatternScrollItem(deck, p));
      }
      patternLists[deck.index] = new UIItemList(1, yp, this.width - 2, 140).setItems(items);
      patternLists[deck.index].setVisible(deck.index == focusedChannel.getValuei());
      patternLists[deck.index].addToContainer(this);
    }
    
    yp += patternLists[0].getHeight() + 10;  
    knobs = new UIKnob[NUM_KNOBS];
    for (int ki = 0; ki < knobs.length; ++ki) {
      knobs[ki] = new UIKnob(5 + 34 * (ki % KNOBS_PER_ROW), yp
        + (ki / KNOBS_PER_ROW) * 48);
      knobs[ki].addToContainer(this);
    }
     
    for (LXDeck deck : lx.engine.getDecks()) {  
      LXDeck.Listener lxListener = new LXDeck.AbstractListener() {
        public void patternWillChange(LXDeck deck, LXPattern pattern,
            LXPattern nextPattern) {
          patternLists[deck.index].redraw();
        }

        public void patternDidChange(LXDeck deck, LXPattern pattern) {
          LXPattern[] patterns = deck.getPatterns();
          for (int i = 0; i < patterns.length; ++i) {
            if (patterns[i] == pattern) {
              patternLists[deck.index].setFocusIndex(i);
              break;
            }
          }  
          
          patternLists[deck.index].redraw();
          if (deck.index == focusedChannel.getValuei()) {
            int pi = 0;
            for (LXParameter parameter : pattern.getParameters()) {
              if (pi >= knobs.length) {
                break;
              }
              if (parameter instanceof LXListenableNormalizedParameter) {
                knobs[pi++].setParameter((LXListenableNormalizedParameter)parameter);
              }
            }
            while (pi < knobs.length) {
              knobs[pi++].setParameter(null);
            }
          }
        }
      };
      deck.addListener(lxListener);
      lxListener.patternDidChange(deck, deck.getActivePattern());
    }
    
    focusedChannel.addListener(new LXParameterListener() {
      public void onParameterChanged(LXParameter parameter) {
        int pi = 0;
        for (UIItemList patternList : patternLists) {
          patternList.setVisible(pi == focusedChannel.getValuei());
          ++pi;
        }
      }
    });
    
  }
  
  void select() {
    patternLists[focusedChannel.getValuei()].select();
  }
  
  float amt = 0;
  void knob(int delta) {
    if (delta > 64) {
      delta = delta - 128;
    }
    amt += delta / 4.;
    if (amt > 1) {
      scroll(1);
      amt -= 1;
    } else if (amt < -1) {
      scroll(-1);
      amt += 1;
    }
  }
  
  void scroll(int delta) {
    UIItemList list = patternLists[focusedChannel.getValuei()]; 
    list.setFocusIndex(list.getFocusIndex() + delta);
  } 

  private class PatternScrollItem extends UIItemList.AbstractItem {

    private final LXDeck deck;
    private final LXPattern pattern;

    private final String label;

    PatternScrollItem(LXDeck deck, LXPattern pattern) {
      this.deck = deck;
      this.pattern = pattern;
      this.label = UI.uiClassName(pattern, "Pattern");
    }

    public String getLabel() {
      return this.label;
    }

    public boolean isSelected() {
      return this.deck.getActivePattern() == this.pattern;
    }

    public boolean isPending() {
      return this.deck.getNextPattern() == this.pattern;
    }

    public void onMousePressed() {
      this.deck.goPattern(this.pattern);
    }
  }
}
