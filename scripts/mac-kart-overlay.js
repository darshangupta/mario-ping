#!/usr/bin/env osascript -l JavaScript
// mac-kart-overlay.js — Mario Kart sprite overlay for macOS
// Usage: osascript -l JavaScript mac-kart-overlay.js <sprite> <signal_file> <assets_dir>
// sprite: kart (default), green-shell, red-shell
// signal_file: path to temp file; overlay exits when file is deleted
// assets_dir: path to mario-ping/assets/

ObjC.import('Cocoa');
ObjC.import('QuartzCore');

function run(argv) {
  var sprite     = argv[0] || 'kart';
  var signalFile = argv[1] || '/tmp/mario-ping-kart-signal';
  var assetsDir  = argv[2] || '';

  // Pick image file
  var imageFile;
  switch (sprite) {
    case 'green-shell': imageFile = assetsDir + '/green-shell.png'; break;
    case 'red-shell':   imageFile = assetsDir + '/red-shell.png';   break;
    default:            imageFile = assetsDir + '/mario-kart.png';  break;
  }

  var isShell = (sprite === 'green-shell' || sprite === 'red-shell');

  $.NSApplication.sharedApplication;
  $.NSApp.setActivationPolicy($.NSApplicationActivationPolicyAccessory);

  // Load the sprite image
  var img = $.NSImage.alloc.initWithContentsOfFile($(imageFile));
  if (!img || img.isNil()) {
    $.NSApp.terminate(null);
    return;
  }

  var imgSize = img.size;
  var imgW    = imgSize.width;
  var imgH    = imgSize.height;

  var screens     = $.NSScreen.screens;
  var screenCount = screens.count;
  var imageViews  = [];

  for (var i = 0; i < screenCount; i++) {
    var screen = screens.objectAtIndex(i);
    var sf     = screen.frame;
    var sw     = sf.size.width;
    var sh     = sf.size.height;
    var sx     = sf.origin.x;
    var sy     = sf.origin.y;

    var winH = imgH + 20;
    var winY = sy + Math.floor(sh / 2) - Math.floor(winH / 2);

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

    // Image view — starts off-screen left
    var iv = $.NSImageView.alloc.initWithFrame(
      $.NSMakeRect(-imgW - 20, 10, imgW, imgH)
    );
    iv.setImage(img);
    iv.setImageScaling($.NSImageScaleProportionallyUpOrDown);
    iv.setWantsLayer(true);

    win.contentView.addSubview(iv);
    win.makeKeyAndOrderFront(null);
    imageViews.push({ view: iv, screenW: sw });
  }

  // Shells spin using CABasicAnimation on the layer
  if (isShell) {
    var spinAnim = $.CABasicAnimation.animationWithKeyPath($('transform.rotation.z'));
    spinAnim.setFromValue($(ObjC.wrap(0)));
    spinAnim.setToValue($(ObjC.wrap(-6.2832)));
    spinAnim.setDuration(0.55);
    spinAnim.setRepeatCount(1e10);
    spinAnim.setTimingFunction(
      $.CAMediaTimingFunction.functionWithName($.kCAMediaTimingFunctionLinear)
    );
    for (var si = 0; si < imageViews.length; si++) {
      imageViews[si].view.layer.addAnimationForKey(spinAnim, $('spin'));
    }
  }

  // Mutable state object — accessible inside NSTimer ObjC closure
  var state = {
    x:     -imgW - 20,
    speed: isShell ? 14 : 10,
    tick:  0,
    maxW:  screens.objectAtIndex(0).frame.size.width
  };

  ObjC.registerSubclass({
    name: 'MarioSpriteAnimator',
    superclass: 'NSObject',
    methods: {
      'tick:': {
        types: ['void', ['id']],
        implementation: function(timer) {
          // Exit when signal file is deleted
          if (!$.NSFileManager.defaultManager.fileExistsAtPath($(signalFile))) {
            timer.invalidate();
            $.NSApp.terminate(null);
            return;
          }

          state.x    += state.speed;
          state.tick += 1;

          // Loop back off-screen left after exiting right
          if (state.x > state.maxW + imgW + 20) {
            state.x = -imgW - 20;
          }

          // Slight speed wobble for kart feel
          if (!isShell && state.tick % 50 === 0) {
            state.speed = 9 + Math.random() * 3;
          }

          for (var wi = 0; wi < imageViews.length; wi++) {
            imageViews[wi].view.setFrame(
              $.NSMakeRect(state.x, 10, imgW, imgH)
            );
          }
        }
      }
    }
  });

  var animator = $.MarioSpriteAnimator.alloc.init;
  $.NSTimer.scheduledTimerWithTimeIntervalTargetSelectorUserInfoRepeats(
    1 / 60,
    animator,
    'tick:',
    null,
    true
  );

  $.NSApp.run;
}
