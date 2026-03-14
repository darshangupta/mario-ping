#!/usr/bin/env osascript -l JavaScript
// mac-kart-overlay.js — animated Mario Kart kart overlay for macOS
// Usage: osascript -l JavaScript mac-kart-overlay.js <character> <signal_file> <event_type>
// Exits when signal_file is deleted (dismiss signal from mario.sh UserPromptSubmit hook)

ObjC.import('Cocoa');
ObjC.import('QuartzCore');

function run(argv) {
  var character  = argv[0] || 'mario';
  var signalFile = argv[1] || '/tmp/mario-ping-kart-signal';
  var eventType  = argv[2] || 'input.required';

  // Character colors
  var chars = {
    mario:    { label: 'MARIO',    r: 0.95, g: 0.1,  b: 0.1  },
    luigi:    { label: 'LUIGI',    r: 0.1,  g: 0.75, b: 0.1  },
    toad:     { label: 'TOAD',     r: 0.4,  g: 0.4,  b: 1.0  },
    yoshi:    { label: 'YOSHI',    r: 0.1,  g: 0.85, b: 0.3  },
    peach:    { label: 'PEACH',    r: 1.0,  g: 0.5,  b: 0.75 },
    bowser:   { label: 'BOWSER',   r: 0.85, g: 0.5,  b: 0.0  },
    waluigi:  { label: 'WALUIGI',  r: 0.6,  g: 0.0,  b: 0.9  },
    rosalina: { label: 'ROSALINA', r: 0.2,  g: 0.65, b: 0.95 },
    donkey:   { label: 'DK',       r: 0.65, g: 0.3,  b: 0.0  },
  };
  var ch = chars[character] || chars['mario'];

  $.NSApplication.sharedApplication;
  $.NSApp.setActivationPolicy($.NSApplicationActivationPolicyAccessory);

  var screens = $.NSScreen.screens;
  var screenCount = screens.count;
  var labels  = [];
  var namelbs = [];
  var streaks = [];

  for (var i = 0; i < screenCount; i++) {
    var screen = screens.objectAtIndex(i);
    var sf     = screen.frame;
    var sw     = sf.size.width;
    var sh     = sf.size.height;
    var sx     = sf.origin.x;
    var sy     = sf.origin.y;
    var winH   = 110;
    var winY   = sy + Math.floor(sh / 2) - Math.floor(winH / 2);

    var win = $.NSWindow.alloc.initWithContentRectStyleMaskBackingDefer(
      $.NSMakeRect(sx, winY, sw, winH),
      $.NSWindowStyleMaskBorderless,
      $.NSBackingStoreBuffered,
      false
    );
    win.setBackgroundColor($.NSColor.clearColor);
    win.setOpaque(false);
    win.setHasShadow(false);
    win.setAlphaValue(1.0);
    win.setLevel($.NSStatusWindowLevel + 1);
    win.setIgnoresMouseEvents(true);
    win.setCollectionBehavior(
      $.NSWindowCollectionBehaviorCanJoinAllSpaces |
      $.NSWindowCollectionBehaviorStationary
    );
    win.contentView.wantsLayer = true;

    // Kart emoji label
    var kartLbl = $.NSTextField.alloc.initWithFrame($.NSMakeRect(-130, 5, 110, 90));
    kartLbl.setStringValue($('🏎'));
    kartLbl.setBezeled(false);
    kartLbl.setDrawsBackground(false);
    kartLbl.setEditable(false);
    kartLbl.setSelectable(false);
    kartLbl.setFont($.NSFont.systemFontOfSize(76));
    kartLbl.cell.setWraps(false);
    win.contentView.addSubview(kartLbl);
    labels.push(kartLbl);

    // Character name label
    var nameLbl = $.NSTextField.alloc.initWithFrame($.NSMakeRect(-130, 82, 120, 18));
    nameLbl.setStringValue($(ch.label));
    nameLbl.setBezeled(false);
    nameLbl.setDrawsBackground(false);
    nameLbl.setEditable(false);
    nameLbl.setSelectable(false);
    nameLbl.setTextColor($.NSColor.colorWithSRGBRedGreenBlueAlpha(ch.r, ch.g, ch.b, 1.0));
    nameLbl.setFont($.NSFont.boldSystemFontOfSize(12));
    nameLbl.setAlignment($.NSTextAlignmentCenter);
    win.contentView.addSubview(nameLbl);
    namelbs.push(nameLbl);

    // Speed streak lines (3 horizontal lines behind kart for motion feel)
    var screenStreaks = [];
    for (var line = 0; line < 3; line++) {
      var lineY   = 18 + line * 26;
      var streakW = 180;
      var sv = $.NSView.alloc.initWithFrame($.NSMakeRect(-streakW - 20, lineY, streakW, 4));
      sv.setWantsLayer(true);
      sv.layer.setBackgroundColor(
        $.NSColor.colorWithSRGBRedGreenBlueAlpha(ch.r, ch.g, ch.b, 0.35 - line * 0.08).CGColor
      );
      sv.layer.setCornerRadius(2);
      win.contentView.addSubview(sv);
      screenStreaks.push(sv);
    }
    streaks.push(screenStreaks);

    win.makeKeyAndOrderFront(null);
  }

  // Mutable animation state — accessible inside ObjC subclass closure
  var state = {
    x: -150,
    speed: 10,
    tick: 0,
    maxW: screens.objectAtIndex(0).frame.size.width
  };

  ObjC.registerSubclass({
    name: 'MarioKartAnimator',
    superclass: 'NSObject',
    methods: {
      'tick:': {
        types: ['void', ['id']],
        implementation: function(timer) {
          // Dismiss check: if signal file deleted, exit
          if (!$.NSFileManager.defaultManager.fileExistsAtPath($(signalFile))) {
            timer.invalidate();
            $.NSApp.terminate(null);
            return;
          }

          state.x    += state.speed;
          state.tick += 1;

          // Loop kart from off-screen left when it exits right
          if (state.x > state.maxW + 150) {
            state.x = -150;
          }

          // Subtle speed jitter every 45 frames for MK feel
          if (state.tick % 45 === 0) {
            state.speed = 8 + Math.random() * 4;
          }

          // Update all screens
          for (var wi = 0; wi < labels.length; wi++) {
            labels[wi].setFrame($.NSMakeRect(state.x, 5, 110, 90));
            namelbs[wi].setFrame($.NSMakeRect(state.x - 5, 82, 120, 18));
            // Streaks trail behind kart
            var sc = streaks[wi];
            for (var li = 0; li < sc.length; li++) {
              var streakW = 180 - li * 20;
              sc[li].setFrame($.NSMakeRect(state.x - streakW - 15, 18 + li * 26, streakW, 4));
            }
          }
        }
      }
    }
  });

  var animator = $.MarioKartAnimator.alloc.init;
  $.NSTimer.scheduledTimerWithTimeIntervalTargetSelectorUserInfoRepeats(
    1 / 60,
    animator,
    'tick:',
    null,
    true
  );

  $.NSApp.run;
}
