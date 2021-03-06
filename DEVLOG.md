# Sat 25 Apr 2015

Game design idea: The germs grow faster when bunched together.

# Wed  1 Apr 2015

Well, after finally getting someone from the UPX to fix a bug with packing ARM executables, I
discover that Apple is pretty thorough in the checks it does on .ipa archives. Here are some of
the errors I got:


      The binary is invalid. The encryption info in the LC_ENCRYPTION_INFO load command
      is either missing or invalid, or the binary is already encrypted. This binary does not
      seem to have been build with Apple's linker.

      Invalid Segment Alignment. The app binary at 'Epidemic.app/Epidemic' does not have
      proper segment alignment. Try rebuilding the app with the latest Xcode version.

      Invalid Bundle. The bundle Epidemic.app does not support the minimum OS Version specified
      in the Info.plist

I inspected an executable before code signing and found that it has a *load command* called
`LC_ENCRYPTION_INFO` which is missing once you compress it with UPX.

For the second error I don't know what the proper segment alignment would be.

The third error I'm pretty sure is caused because of a missing `LC_VERSION_MIN_IPHONEOS` load
command.


The upshot of this is that
unless we can rewrite UPX to respect these headers, keep them around somehow, then we're never
going to be able to submit something to the App store.



This problem is too big for me to solve by myself.


# Tue 31 Mar 2015

On iOS I have just found that in the following code, the `glBindBuffer gl_ARRAY_BUFFER 0`
is *very* important. On Android it did not seem important.

    glBindBuffer gl_ARRAY_BUFFER vertexBuf
    glBufferData gl_ARRAY_BUFFER (fromIntegral bufSize) vs gl_STATIC_DRAW -- P1
    glBindBuffer gl_ARRAY_BUFFER 0

I have not yet determined the reason.


# Fri 27 Mar 2015

## Slow blur shaders

There is something just plain slow about the way I'm *invoking* the blur shader. Even when I
comment most of it out so that it's barely performing any calculations at all it still runs slowly
at about 50 f/s on the iPhone Simulator. That's slow.

I'm pretty sure that I'm recalculating a lot of stuff. Also, I'm going to try using VBOs this time
around.

I notice that 50 f/s is half of the 100 f/s that seems to be about the limit of what I've ever
got on the iPhone Simulator.

## CADisplayLink and OpenGL ES Tools in Xcode 6

I couldn't get timings that I can see in some of the pictures [here](https://developer.apple.com/library/ios/documentation/3DDrawing/Conceptual/OpenGLES_ProgrammingGuide/ToolsOverview/ToolsOverview.html).

    Note: Some features of the FPS gauge and GPU report rely on a display link timer. If you do not
    use the CADisplayLink  or GLKViewController classes to animate your OpenGL ES displays, the
    gauge and report cannot show performance relative  to a target frame rate or provide accurate
    CPU frame time information.

It turns out it's because we're not using a `CADisplayLink`. I had a look through the SDL2
source code and there is a `startAnimation` method that uses it. However, I'm not using
animation callbacks in my game, so `CADisplayLink` is not being used.

# Thu 26 Mar 2015

## 11:00

Last night I turn `ProfileGraphics` into just another module that one imports rather than
the main module for a separate program. This is good because it now means I can run the
profile code on iOS and Android with minimal changes.

I can safely say after all this work that the shaders are not the source of the performance slow
down. The slow down may well be due to many "not best practice" things I'm doing.

This [page](https://developer.apple.com/library/ios/documentation/3DDrawing/Conceptual/OpenGLES_ProgrammingGuide/TechniquesforWorkingwithVertexData/TechniquesforWorkingwithVertexData.html)
looks like it's going to very useful in helping me improve the performance of my code.

One thing I've realised is that I repeatedly send vertex array data. I do it once for each germ.
Perhaps it would be better to send this data all at once and then get each germ to draw itself
from portions of the vertex array by changing the `first` offset in `glDrawArrays`.

I also need to look into VBOs and VAOs and also the `glMapBufferRange` extension.

I need to know a little bit more about these extensions. Are they supported on all devices or does
one need to performance a check in software when initialising OpenGL and then use the code
only when that extension is available? I suspect it's the latter.

Here are some answers:

- VBOs are suppored in GL ES 2.0
- VAOs need to be checked for as an extension. Otherwise don't use them.


## 13:40 Plain old blur is slow!

The blur effect is just plain old slow. 3 fps on iOS Simulator. (Yes, really that low!) I'm sure
this just can't be right and I'm doing something horribly wrong. I wonder what it is.


## 15:34 It's texture2D calls that are slowing it down

I removed all the texture2D calls from the guassian blur and it's back up to being very fast again.

From [Best PracticesForShaders](https://developer.apple.com/library/ios/documentation/3DDrawing/Conceptual/OpenGLES_ProgrammingGuide/BestPracticesforShaders/BestPracticesforShaders.html) we have
the following information on *dependent texture reads*. (Remember this term!)

    Dynamic texture lookups, also known as dependent texture reads, occur when a fragment shader
    computes texture coordinates rather than using the unmodified texture coordinates passed into
    the shader. Dependent texture reads are supported at no performance cost on
    OpenGL ES 3.0–capable hardware devices; on other devices , dependent texture reads can delay
    loading of texel data, reducing performance. When a shader has no dependent texture reads, the
    graphics hardware may prefetch texel data before the shader executes, hiding some of the latency
    of accessing memory.

(This explains why it runs nice and fast on my Mac. The hardware can perform these calculations
 at no cost.)

An example of a program with a dependent texture read is:

    varying vec2 vTexCoord;
    uniform sampler2D textureSampler;

    void main()
    {
        vec2 modifiedTexCoord = vec2(1.0 - vTexCoord.x, 1.0 - vTexCoord.y);
        gl_FragColor = texture2D(textureSampler, modifiedTexCoord);
    }

My blur fragment shader has *eight* dependent texture reads. Ouch. The trick is to move these
into the vertex shader.

## 16:40 Hell yeah, pre-calculating texture co-ordinates speeds things up a lot!

Android: Went from 12fps to 52fps. (That's still below 60 so we've got more to do.)
iOS Simulator:



# Wed 25 Mar 2015

## First profiling results

Commit: d7e0eddeb03ac17cb50e458f1c9ebab3f8b668e5

- justGerms: 800-830 fps
- blurSeparateShaders: 335-345 fps


## Profiling - refactoring

In trying to refactor to easy profiling I'm going to try out the trick where you have two
modules with exactly the same interface but you only import the one you need.

## Profiling

So, I'm sanguine about the idea that I can still pass around values of type `WorldGLSL` or
`BlurGLSL` but have them be initialised differently for two different GLSL programs.

I need to separate out the idea of a data structure containing uniform/attribute locations from the
idea of a data structure containing the program ID.

Presumably, my "all in one shader" will create a `WorldGLSL` and a `BlurGLSL` value.

Let's look at the design of this. I used to have this data structure.

    data GLSLProgram a = GLSLProgram { glslVertexShader   :: String
                                     , glslFragmentShader :: String

I think I'm going to rename this to `GLSLSource` and now create a new data structure:

    data GLSLProgram a = GLSLProgram { glslProgramId      :: ProgramId
                                     , glslAPI            :: a
                                     , glslInit           :: GLM ()
                                     }

I'm planning to instantiate `glslAPI` with either `WorldGLSL` or `BlurGLSL`. But I also need the
`glslInit` field in order to initialise the program to use the API in `glslAPI`. For my current
situation where I have a distinct program for world rendering and for blurring this will
just be `return ()`, but when I use "one big shader" it will set an important uniform(s) that
will choose which subroutine(s) of the "one big shader" to use.

## Refactoring is a dream in Haskell

I just performed that whole refactor in less than 30 minutes. I cannot imagine doing this in a
language that didn't have such a strong typing system. Scala, Haskell, OCaml are all languages
that would have been equivalently easy. I cannot imagine having done this in Ruby.

The fact that once all the compiler errors went away, I compiled the program and it worked just
as it did before is as astounding to me today as it was the first time I performed a refactor
like this. Strong type systems makes refactoring easy, okay! That is one of its key strengths.

# Tue 24 Mar 2015

## The problem of profiling in perpetuity

This is a bit of a conundrum. I want to test a few different GLSL programs to see which is the
fastest. I also want to keep the profiling program around so that I can test any time I make
a small change to one of the GLSL programs. The idea is I will only keep the programs that are
the fastest.

The problem is that this requires me to do one of two things with my existing OpenGL code.

a) I generalise it sufficiently that you can "plug in" various GLSL programs or
b) I copy code. I copy older versions of GLSL programs into module ProfileGraphics.


# Fri 20 Mar 2015

Apparently branch in shaders is particularly bad. First I want to get a feel for why this is so.


# Thu 19 Mar 2015

I spent almost all day working out why I had a "magenta screen of death" on the iOS Simuator.
The answer was really hard to track down, but was actually aided by going back through my
repository and finding the commit that introduced the bug in the first place. It turns out that

    glBindFramebuffer gl_FRAMEBUFFER 0

does not work on iOS! The frame buffer ID for the screen is simply not zero. You can, however, get
it with (in C)

    glGetIntergerv(GL_FRAMEBUFFER_BINDING, &val)

Now we have the problem that the game is a *lot* slower on Android and iOS with the blur effect.

## Performance tuning

It seems that creating "one big shader" is actually a good idea.

See [here](http://stackoverflow.com/questions/16096661/opengl-performance-overhead-from-frequently-swapping-between-two-shaders)

    changing the shaders flushes the GPU execution pipelines. And it takes a few dozen clock cycles
    for the pipelines and branch predictors to settle for the newly switched to shader.

# Wed 18 Mar 2015

Game design:

* in app purchases
* sharing top scores with social media

# Tue 17 Mar 2015

Game design feedback.

My friend Tim mentioned that the exponential nature of the game is what makes it surprising.
Unless you get the germs nice and early you suddenly lose control. It's how things work, but is
this fun?

---

Game design idea:

* focus at germs on different "levels" to kill them all. This might be a way to slow the action
  of the game down.


# Wed 11 Mar 2015

It seems it may have become necessary for me to introduce a new abstraction to the Game layer.
The game is responsible for drawing things to the screen so we can't escape the fact that
it has to "know" about the screen. What I wanted to avoid however, was it having to know
anything about OpenGL. I wanted to keep that part of the game safely encapsulated.

Thus was born the GLM monad. However, it's currently not very opaque at all.
...
Okay I just fixed that.

Now that this is opaque I think I want to introduce the concept of a background and a foreground
screen. I then want to layer these two on top of each other. (In future I want to have blurred
germs in the background that you can't interact there, just for eye candy.)

I probably need to move a whole bunch of functionality from the Backend.SDL to GraphicsGL
(so it's all self-contained). We could then tag the GLM monad with a type that will
let us know which of the GLSL programs to run.

e.g. if type is `GLM Foreground a` then use the `textureGLSLProgram` (which should probably be
renamed to `foregroundGLSLProgram`)

---

Hack, hack, hack. Yes, this technique worked and it's quite good! It prevents me from
combining GLM functions in the wrong order in module Game.

I now have two "layers" in the GameState, one for the "world" GLSL program and one for "screen".
I have to make sure to update "screen" each frame. Soon I'll add a "background" too.

---

Another game design idea:

* The play must bring the petrie dish into focus.

# Sun 8 Mar 2015

A check list for debugging on Android

* Make sure you used the `adb shell setprop log.redirect-stdio true` trick below to see all
  messages using `adb logcat`

# Sat 7 Mar 2015

More game design ideas:

* Add Konami code to unlock some kind of easter egg.
* Vibrate the phone when the germs die.

---

I've found a great utility that compresses executables. I added a new "Run Script" phase
to the Xcode build and then used this script

${SRCROOT}/upx --lzma ${CONFIGURATION_BUILD_DIR}/${EXECUTABLE_PATH}

Worked like a charm right up to the code signing. Code signing used to work with UPX but not at
present. I found a bug report and I think if I pester the developers I might get this
added.

http://sourceforge.net/p/upx/bugs/229/

It significantly compresses the executables so it will be worth it.

---

# Thu 5 Mar 2015

I'm still vaguely unsatisfied. What if I'm wrong. There needs to be an experiment that I can
carry out that proves that the fonts don't render properly at certain sizes.

---

Okay, first I verified that when I try to render the text "SCORE:" at a length 114 pixels then
it renders at a width of 116 pixels. I did this using the `cairo-interactive.sh` script I wrote
a week ago. This proved that the problem was with Cairo (or Freetype) but not OpenGL.

I then discovered the reason. Fractional font sizes are not supported! (See question 26
[here](http://www.freetype.org/freetype1/docs/faq/freetype1.txt).) If you specify size=36.6
then it acts as if it is size=37. Thus it renders larger than it should be and bursts out of its
bounding box. It's just a stroke of luck that we noticed it at 960x640. It could have happened at
any resolution.

The solution is simple. Find the notional font size and *truncate* it. Then recalculate the
"text extents" to find the true width and leave a little margin on either side. The "length"
argument now specifies the *maximum* width for the text to display at, and the system tries
its best to fit it in.

I'm really pleased that I listen to my gut and kept beavering away at this problem until I had
cracked it.

# Wed 4 Mar 2015

Let me reason through a problem. On iOS the text is clipped a little. I can only assume this
is because the values coming back from Cairo for text sizes are slightly different.

I think I will log on Mac OS X and iOS and see what the differences are.

I've done that now. The values coming out where not the same but they were close.

     bx=29.97, by=-7730.06, tw=30830.39, th=8830.03

vs.

     bx=29.94, by=-7730.04, tw=30830.25, th=8830.02

So, the problem must be somewhere else.

Breakthrough! When I set the Mac OS X resolution to 960x640 I got the same problem as I get on
iOS. So it has nothing to do with iOS and everything to do with an incorrect calculation somewhere.
The aspect ratio is 3:2 in this case.

Now testing with larger resolutions (at same aspect ratio)
  1020x660: no bug
  1284x856: no bug

Now testing at sub 1000 pixel widths:

  954x636: bug
  966x644: bug
  750x500: bug

Okay, what do we know

  * orthoBounds are correct
  * renderToQuad correctly finds the right width and height of rectangle to render

---

It's now hours later. Seriously, it's about 7 hours later.
Cairo just doesn't render fonts correctly at certain widths. I've added a kludge to scale the
render by 0.97. This seems to fit now.

I really wanted to solve this correctly, but it's not my issue it seems.


# Sun 29 Feb 2015

## Building GHC from source

In order to build an aarch64 cross compiler I had to build from the wip/llvm-3.6 branch of
GHC. Erik de Castro Lopo told me about a command I needed to run after having download the
source.

    git submodule update --init --recursive --rebase

I now wanted to break down exactly what that does. Here are the relevant parts of the man page.

    update
        Update the registered submodules, i.e. clone missing submodules and
        checkout the commit specified in the index of the containing repository.
        This will make the submodules HEAD be detached unless --rebase or --merge
        is specified or the key submodule.$name.update is set to rebase, merge or
        none.  none can be overridden by specifying --checkout. Setting the key
        submodule.$name.update to !command will cause command to be run.  command
        can be any arbitrary shell command that takes a single argument, namely
        the sha1 to update to.

        If the submodule is not yet initialized, and you just want to use the
        setting as stored in .gitmodules, you can automatically initialize the
        submodule with the --init option.

        If --recursive is specified, this command will recurse into the
        registered submodules, and update any nested submodules within.

        If --force is specified, the submodule will be checked out (using git
        checkout --force if appropriate), even if the commit specified in the
        index of the containing repository already matches the commit checked out
        in the submodule.

    --recursive
        This option is only valid for foreach, update and status commands.
        Traverse submodules recursively. The operation is performed not only in
        the submodules of the current repo, but also in any nested submodules
        inside those submodules (and so on).

    --rebase
        This option is only valid for the update command. Rebase the current
        branch onto the commit recorded in the superproject. If this option is
        given, the submodule's HEAD will not be detached. If a merge failure
        prevents this process, you will have to resolve these failures with git-
        rebase(1). If the key submodule.$name.update is set to rebase, this
        option is implicit.

    --init
        This option is only valid for the update command. Initialize all
        submodules for which "git submodule init" has not been called so far
        before updating.

The bit I'm confused about it `--rebase`. Is it a good idea?

After a discussion with Erik, I've decided it's probably *not* what I want. So I will no longer
use the `--rebase` option.

## Configure command for GHC 7.11 on wip/llvm-3.6 branch

    ./configure --target=aarch64-apple-darwin14 \
      --with-ghc=$HOME/ghc-ios/host-sysroot/bin/ghc \
      --enable-bootstrap-with-devel-snapshot \
      --with-gcc=aarch64-apple-darwin14-clang \
      --enable-unregisterised \
      --with-ld=aarch64-apple-darwin14-ld \
      --with-llc=/usr/local/clang+llvm-3.6.0-rc2-x86_64-apple-darwin/bin/llc \
      --with-opt=/usr/local/clang+llvm-3.6.0-rc2-x86_64-apple-darwin/bin/opt \
      --prefix=$HOME/ghc-ios/aarch64-sysroot

Notice the use of a host compiler `$HOME/ghc-ios/host-sysroot/bin/ghc`. You need to build
this first and then use it. I had problems building, that I cannot recall,  otherwise.
This is known as a "stage 0" compiler.

The `aarch64-apple-darwin14-clang` script is:

    #!/bin/sh
    TARGET_PLATFORM=`xcrun --show-sdk-path --sdk iphoneos`
    TARGET_GCC=/usr/local/clang+llvm-3.6.0-rc2-x86_64-apple-darwin/bin/clang
    TARGET_CFLAGS="-isysroot $TARGET_PLATFORM -arch arm64 -miphoneos-version-min=7.0"

    exec $TARGET_GCC $TARGET_CFLAGS "$@"

and the `mk/build.mk` has to be:

    BuildFlavour  = quick-cross

# Sat 28 Feb 2015

Game play idea. Perhaps the area of effect of an antibiotic should not the complete screen.
As the antibiotics get less potent they fade in colour until they become
clear eventually.

---

I discovered that once I've installed from Google Play I can't do my ordinary Android
'full-build.sh' to get it on my phone. I must first uninstall it and then run 'full-build.sh'
again.

---

Naming convention for beta builds

First 6 digits of following two SHA1 hashes:

1. epidemic-game commit.
2. iOS/Android repo commit just before bumping version.

e.g. I am in the Android repo and I have first six digits of 'epidemic-game' repo of 09f633
and first six digits of last commit in Android repo was 0258cb. Then my bumped version string
is: "09f633-0258cb"

# Fri 27 Feb 2015

I've got a nice flask graphic but now I want to make the contents of the flask fade out
slowly as the antibiotic becomes less effective. If I was drawing each frame this would be easy.
Just use a different colour each time, but I've switched to using a one-time mipmapping
strategy.

But wait, this was only for performance reasons! There's no problem with redrawing the graphic
each time with a slightly faded colour. I don't even need to mipmap since the graphic is never
scaled, unlike the germs.

# Wed 25 Feb 2015

More feedback:

* It's not clear when you're "about to die" in the game. Perhaps make that clearer.

# Mon 23 Feb 2015

Turns out that I need to put up a different version of the game on Google Play that is free.
I only needed to do a few things:

a) Change the `name` field of the `<project>` tag in `build.xml`. (I added a ".beta")
b) Create a new private key alias "epidemic-beta" and sign with that. Do this by
   editing `ant.properties`.
c) Change title of app to "Epidemic Beta" in `res/values/strings.xml`
d) Change the package name in `AndroidManifest.xml`. This is the path to the java source.
e) Create a new class `src/com/declarative/games/epidemic/beta/Activity.java`

This is the key signing command.

     keytool -genkey -v -keystore declarative-games.keystore \
       -alias epidemic-beta -keyalg RSA -keysize 2048 -validity 10000

---

I want to create an interactive environment where I can reload and display Cairo graphics from
GHCi. Nothing too fancy. No need to watch a file and recompile it each time it changes.
I'm quite happy just to type

    :r
    display <some cairo effect>

What I want it to is render the Cairo graphic to a PNG and then open that with Preview.
I can't imagine this is going to be too hard.

# Sun 22 Feb 2015

I've decided to not work on anything but my game for another month. Hopefully I can get at least
100 hours more done on the game by the end of March.

---

Some more design ideas

* smaller germs that move around in the background and don't really do anything.
* small, cigar shaped germs (perhaps with cillia!) that move around in the foreground and are
  hard to catch.
* hold down on a germ instead of tapping it and watch its health drop. Can hold down a maximum
  of n germs at a time. Perhaps you unlock "holding down multiple germs at a time" as a power.
* germs should shrink from a death. Could yield some really nice flocking behaviour or allow you to
  herd them.
* Perhaps germs consume food in order to grow? Then herding them would be a good way to keep them
  from growing further.

---

If I'm really going to get some good data of a game, I think I'm going to need to be able to
record games. Thinking about this reminds me of a Gamasutra article I saw years ago in which
someone spoke about floating point error leading to chaotic behavior. I'm going to have to record
something like

* cumulative time
* stats of every germ. Position, size, etc
* event times.

I then need to get people to send me the recordings and play the recordings to see how people
are playing the game.

# Wed 18 Feb 2015

I wanted to record what I wrote to Rauri about the performance of Cairo in drawing germs.

"For resolution 568x320 (the non-retina display resolution of an iPhone 5) we get that
drawing 400 germs has a theoretical maximum frame rate of ... 43 frames/s. This is with no game
logic and certainly no physics."


# Fri 13 Feb 2015

Learned all about signing apps today. On Android you manage your own keystore and private keys
for signing your apps.

http://developer.android.com/tools/publishing/app-signing.html

---

I've now managed to sign an app and upload it to the Google Play store. I've also created
a Google Group called "Declarative Games Epidemic Testers". I can't yet publish the game because
there are a whole bunch of things I need to fill in:

* You need to add a high-res icon. [English (United Kingdom) – en-GB]
* You need to add a feature graphic. [English (United Kingdom) – en-GB]
* You need to add at least 2 non-Android TV screenshots. [English (United Kingdom) – en-GB]
* You need to select a category.
* You need to select a content rating.
* You need to add a short description. [English (United Kingdom) – en-GB]
* You need to add a full description. [English (United Kingdom) – en-GB]
* You need to acknowledge that this application meets the Content Guidelines.
* You need to acknowledge that this application complies with US export laws.
* You need to target at least one country.
* You need to enter a privacy policy URL.
* You need to make your application free or set a price for it.

Okay, ouch. Will do this soon.

---

Hah, all of this wasn't that hard to do. Just filled it in with a bunch of dummy data.
No problem at all.

# Thu 12 Feb 2015

To learn more about the directory structure of an Android project.

http://www.compiletimeerror.com/2013/01/directorystructure-of-android-project.html#.VNvc4mSUc6E

# Mon 09 Feb 2015

Trying to build GHC aarch64:

Things I've learned so far

* Don't use LLVM 3.0 as Luke Iannini suggested for GHC ARM and GHC i386.
* Doesn't look like 3.5 is support by GHC
* Homebrew LLVM 3.4 doesn't have -arch arm64. Tried:
    `brew install llvm34 --with-clang --all-targets`
  That didn't work
* Got on #haskell on irc.freenode.net. Was told that LLVM 3.6 is the one you need to use and
  must use branch `wip/llvm-3.6`.
* "perf-cross" does not work as a target in `mk/builk.mk`. Will file ticket on GHC Trac.
* You need to do a `git submodule update --init --recursive --rebase` when you are building
  from HEAD. It syncs each submodule to the same date.
* Had a problem with module System.Posix.Directory.Common not building because of `fdatasync`

    error: implicit declaration of function 'fdatasync' is invalid in C99 [-Werror,-Wimplicit-function-declaration]

  I have not fixed the problem yet but was able to change HAVE_FDATASYNC
  (in `libraries/unix/include/HsUnixConfig.h`) to:

    #define HAVE_FDATASYNC 0

Compiler built fine after that!

---

Still, not everything is rosy. When I try to build something with cabal I get

    ghc: ghc no longer supports single-file style package databases
    (dist/package.conf.inplace) use 'ghc-pkg init' to create
    the database with the correct format.

Austin Seipp says [here](http://comments.gmane.org/gmane.comp.lang.haskell.ghc.devel/6222) that
I need to update to Cabal HEAD to get this to work.




# Sun 08 Feb 2015

Today I finally got the game building on an iPhone. However I almost immediately got this error:

    internal error: stg_ap_v_ret

A little snooping in the GHC RTS source code shows that this symbol will NOT be defined when
you've got CPP symbol `TABLES_NEXT_TO_CODE` defined. I'm sure I've seen this string somewhere
before while a big build has been going on.

More investigation revealed that `-DTABLES_NEXT_TO_CODE` is pass as an option to
`arm-apple-darwin10-clang` during the building of Epidemic.

So, why is this symbol ever called by a running program?

Even on x86_64 architecture `-DTABLES_NEXT_TO_CODE` is defined when building object files with
`gcc`.

---

Update. It turns out that my reasoning is probably flawed.

The GHC Trac "report a bug" [page](https://ghc.haskell.org/trac/ghc/wiki/ReportABug) says that
if you get `stg_ap_v_ret` it's just a run-time error and can occur for all sorts of reasons.
A new ticket should be lodged for any of these.

---

Then I found this on the iOS cross-compling wiki:

"Set Dead Code Stripping to No. This is needed because GHC generates "tables next to code", and without this setting, Xcode thinks the tables are dead code and strips them, causing a crash."



# Wed 04 Feb 2015

More design ideas.

- Germs move. Some germs eat other germs. (This can be a good thing!) But they also grow
  faster.

- As germs divide their division times goes down so that you can't just sit in one level getting
  an awesome score.



# Mon 02 Feb 2015

Was having an intermittent problem with `_ZCMain_main_closure` not being exported in
`libEpidemic.a` for iOS Simulator version of game. Adding `-no-hs-main` to the `ghc-options` in
`Epidemic.cabal` seemed to fix the problem.

---

The next problem I want to tackle is how to load assets for the Android version of the game.
After a little reading it seems the best thing to do is extra the assets files from the APK
and place them on the device somewhere, and then load them.

The Java method that should be used to get a directory for these files is this one:
http://developer.android.com/reference/android/content/Context.html#getExternalFilesDir(java.lang.String)

I'll then have to work out a way of sending that directory path to the Haskell application.

*Sigh* I'm going to have to write some Java code.

# Fri 30 Jan 2015

When you are installing arm-apple-darwin10-ghc make sure you edit the 'settings' file after the
./configure!

    $ ./configure
    $ nano settings

Now change all occurrences of `/usr/bin/gcc`.

    $ make install

# Wed 28 Jan 2015

I'm tired of more Haskell dependencies! My problem today is that I want to use Cairo's freetype2
support. This will require:
  a) the freetype2 binding
  b) more function bindings in the Haskell Cairo binding AND have it match up with the freetype2
     binding.

I think the solution is actually quite simple: don't write this code in Haskell. Write it in C.
Load the TTF file, create the font, and then pass that to the Haskell code. Simple.

# Tue 27 Jan 2015

Today I tried to build Cairo with Quartz support. After finally finding this patch
(https://www.libreoffice.org/bugzilla/attachment.cgi?id=110168) at chaging
configure.ac I succeeded.

This idea was that now I would be able to use Quartz fonts on iOS. It turns out
that the Haskell Cairo binding does not provide bindings to either the Quartz or
Freetype backend.

I have two choices now. Provide the bindings to Quartz or provide bindings to Freetype.
The latter is probably the better long term plan since I'll be able to use that on Android.

* Quartz
  - Pros: Nice fonts. Have already built Cairo with Quartz support
  - Cons: Will still have ugly fonts on Android.

* Freetype
  - Pros: Consistent fonts on iOS and Android
  - Cons: May not be able to build freetype for iOS easily. A cursory glance on the Internet
     shows that this may not be a problem: https://librocket.com/wiki/documentation/BuildingFreeTypeForiOS

# Thu 22 Jan 2015

Why, oh why didn't I come to this co-working space immediately?

Immediate benefits.

1. I can see what other people are doing and raise my development to that level.
2. People would see my game almost immediately and they would have some idea about whether it
   sucked or not. Immediate feedback.
3. I can go to others for technical discussion and troubleshooting.
4. I can get help with publishing and marketing.

# Tue 13 Jan 2015

Today I want to think through tapping, selecting, dragging and dropping. I'll use the term
"press" to denote either a mouse down or a touch down and the term "release" to denote either
a mouse up or touch up. And I'll use the term "move" or "motion" for a mouse motion or touch motion.

So, I want there to be a notion of an event known as a
  - *tap*. A short press and release in roughly the same spot.
  - *select*. Press in a spot and hold there.
  - *drag*. Press in a spot and then move while staying pressed.
  - *unselect*. Release after a *select*.

The last thing I want is to present a non-atomic interface to the game. I don't want the game
logic to have to record the fact that there was the initial "press down" and then later
determine that it was a *select* or a *tap* based on how much time has elapsed.

Perhaps we could do this:

The initial press down causes a *select* event to fire immediately. If it is released within
a small amount of time in roughly the same area then a *tap* event is sent. If a move occurs
then a *drag* event is sent.

This will require state to be kept on a press (i.e. time and location). Once a release occurs
we can then determine whether it was a tap or not.

----

I have two choices
  1. return a *select* event immediately and then a *tap* event if the release is soon enough.
  2. return a *tap* event only and return a *select* each time events are polled and a
     press has not be released in time.

In scenario 1 the following event traces occur:
  - germ kill:       [select', tap]
  - germ move:       [select', drag', unselect]
  - antibiotic drag: [select', drag', unselect]

In scenario 2 the following event traces occur:
  - germ kill:       [tap]
  - germ move:       [drag'] or [select, drag', unselect]
  - antibiotic drag: [drag'] or [select, drag', unselect]

The events marked with primes (') would occur immediately with no delay. Those without primes
have a 100ms (or so) delay. There is no getting around the fact that a tap has to have a delay.

----

Another issue that we need to consider is that of how many SDL events will be processed and emitted per frame. The current implementation can consume an arbitrary number of SDL events
(most of which it ignores) but it will emit at most one event.

I used to think this was a good idea but now I think it should be changed so that multiple events
can be emitted each frame. This will allow a smooth multi-tap experience on touch devices.
(i.e. players can kill more than one germ)

----

I've just discovered yet another problem. While rapidly clicking around the field on germs
it is often the case that the event comes back as a *drag*! This is because a small amount of
movement is occurring in between the press and release.

The solution will have to be that a *select* event must occur before a *drag*.


# Mon 12 Jan 2015

What exactly is a tap?

Up until this point I have defined a tap as a "finger down", but this isn't really accurate.
A tap is a finger down and then a finger up in quick succession. In fact you could define it this
way. We have two events Fd and Fu. These two events combined are a "tap" if
  a) Fu.time - Fd.time < dt
  b) distance(Fu.pos,Fd.pos) < dd

where dt and dd are arbitrary constants.



# Sun 11 Jan 2015

Added a uniform variable "drawTexture" to the fragment shader that chooses between drawing a
plain color polygon or a texture mapped one.


----

Found a bug on Android. I was using glUniformui which is not in GL ES 2.0! Had to use
glUniformi instead.

Was getting this for `adb logcat`

    E/libEGL  ( 1062): called unimplemented OpenGL ES API

Check for that next time things mysteriously fail.


# Sat 10 Jan 2015

Emotional: hating this today. Got slowly better over time.

I came up with some more design ideas while riding on my bike to Adventure Golf today.
  - germs take multiple hits to kill. Cell wall gets thinner or they fade.
  - when damaged their growth rate is limited. If this is non-linear (i.e. biggest hit
    occurs at the beginning then it might make sense to come back and mop them up later,
    especially if by being there they perform some kind of inhibitory action.)

# Fri 9 Jan 2015

I've decided to shift the action of the game over to the right of the screen and put a side bar on
the left. This is where the antibiotics and score will show. For now I have shifted the
co-ordinate system over so that the origin is not in the centre of the screen but in the centre
of a square on the right hand side. i.e.


    +---+---------+
    |   |         |
    |   |    x    |
    |   |         |
    +---+---------+


It's important that it's all one co-ordinate system since people will be dragging and dropping
antibiotics from the side panel on top of the germs.



# Thu 8 Jan 2015

Today I tried to make sure that when I rendered Cairo graphics to an OpenGL texture it
drew on top of transparent white. The problem was the Cairo graphics were anti-aliasing
as if they had a black background. It was really clear.

My first attempt at solving this problem was to draw a transparent white rectangle (in Cairo)
and then render the graphics on top of that. This did not work. Since the alpha value was zero
Cairo treated the background as if it wasn't there. Further study of Cairo's compositing operators
yielded no solution.

The trick to solving this was to initialise the very buffer of 32-bit words that Cairo was
rendering to. It seems there is quite a difference between:
  a) rendering Cairo to a buffer
  b) compositing one Cairo object on top of another.

In case a) if the buffer already contains transparent white (i.e. alpha = 0) values then the anti-aliasing will work as if there is a white value there.

# Mon 5 Jan 2015

I thought I had found out the reason for the unspeakble hack I had to add to Haskell package OpenGLRaw (i.e. directly loading libGLESv2.so using dyld). But it was not the case:

I thought the reason was because I had failed to add:

    System.loadLibrary("GLESv2");

in `SDLActivity.java`.

This has not turned out to be the case. Investigate further.


# Sun 21 Dec 2014

I've now settled on a new solution for drawing germs. I'm no longer going to draw the germs "on
the fly" using Cairo. It's simply too slow, especially on a mobile. What I'm going to do instead
is used mipmapped textures in OpenGL and distort polygons to make the germs "wiggle".

Mipmapping is a pretty wonderful techinique. You take a texture, and the draw it at various
powers of two resolution. i.e.. 512x512, 256x256, 128x128 etc, all the way down to 1x1.
You can then use trilinear filtering to smoothly scale the texture to any size in between.

The problem for my game is that I wanted my germs to wiggle and move. Although theoretically
not perfect, I have found that if I map the texture onto a polygon and then move the points
of the polygon this is a pretty decent effect.

A solution that was initially appealing but that I had to throw out, was to generate several
seconds of a germ animation and mipmap each frame. This was far too expensive in terms of memory.
For 5 seconds animation I needed 300 frames, and that is just for one germ.

# Thu 18 Dec 2014

Today I ran into two strange problems on Xcode which took me some to sort out.

1. I tried to move the i386 libraries for the iOS Simulator into their own subdirectory.
I did this because I also want to put the libraries for other architectures in their own
subdirectories.

But I started getting the

    Application didn't initialize properly, did you include SDL_main.h in the file containing your
    main() function?

I could not find a better way to resolve this than to remove all the lib files and then add them
again. Do things like resetting the iOS Simulator did not work.

2. I discovered there was a problem with `HipMunk`. I used to define `__LP64__` to force it to
use doubles instead of floats. I changed the project so that I just defined `CP_USE_DOUBLES` and
this built a library which then built against Epidemic with type errors. But, it did not
produce the right behaviour on the iOS Simulator! The germs moved around in very strange ways
and the game quickly crashed. So, now I'm defining `__LP64__` even though I don't know why it
works!

It seems to me like it shouldn't since I'm building for the i386 architecture. How can saying
that longs and pointers are 64 bits (which is what `__LP64__` does) work?

# Wed 17 Dec 2014


So I was experiencing a lot of "tearing" when I was running the game
on external monitor but not on my laptop alone.
According to the SDL migration guide (https://wiki.libsdl.org/MigrationGuide)

I was directly rendering into a texture, and then copying that to video
memory using `renderCopy`.

The recommended practise is to
  - draw the entire frame to a buffer in RAM
  - Copy that to the texture
  - Use `renderCopy`

I'm still trying to work out why this is fast at all. Wouldn't copying
straight from a surface to video memory be the way to go? But looking
at the SDL2 library it seems that textures are the *only* way to render
to video memory. Either you copy into textures or you use
`createSurfaceFromTexture`.


# Sun 14 Dec 2014


Breakthrough. The game is now running on iOS simulator.


# Sat 29 Nov 2014


I finally thought of a more "strategic" redesign of the game. Here are some
ideas:

1. The germs don't have to be killed with one tap. The "cell wall" can get
   thinner and thinner until they "pop".
2. There can be different types of germs.
   a) ones that inhibit the growth of others
   b) ones that multiply very fast.
   c) ones that actually kill others that they are in contact with

3. You can pick up and drag a germ?

4. Antibiotics are dragged and dropped. Then a new vial or beaker appears.
   As they get more and more ineffective their colour fades.


# Fri 14 Nov 2014

I finished the Android build on Mon 03 Nov 2014. I'm amazed it worked the
first time because just today I tried to build again and deploy. I discovered
that you get no information on what went wrong when your program
crashes because the stdio and stderr are redirected to /dev/null.

You can get set a property to redirect to the log

    $ adb shell stop
    $ adb shell setprop log.redirect-stdio true
    $ adb shell start

Once you've done this you can

    $ adb logcat | grep 'I/stdout'

or

    $ adb logcat | grep 'I/stderr'

to see output from the program



# Sat 01 Nov 2014


## 15:54

So I've decided to create a number of "third party" repos (which I will
host on GitHub). In these I will check out a particular version of a C
library that I require on Android and port it to build on Android.
I've become a little obsessed with being able to match the files I check in
against a very particular version of the library. I thought that I might
be able to do this by creating a script the re-tars all the files at a
specific git commit hash and then checks the SHA1 hash of this tarball against
the original. This didn't work because tar keeps a whole lot of extra
information around than just the file contents such as file permissions,
time stamps and user/group information. *Sigh*. Annoying.

However, there is another way that we can check. We do keep around the SHA1
hash and the git commit hash in a file in the repo. Then you can download
that file for yourself, untar it into the repo over the top of the files
and see if there is any difference. Then you will know that everything is okay.

----

I've started trying to build the game on Android and this has been a deep,
dark pit of despair so far. I tried following some instructions I found on the
Haskell wiki on building a GHC Arm cross compiler. These did not work too
well for me so I wrote some emails to people who had succeeded before. Ivan
Perez from Keera Studios was very helpful and pointed me to a fork with
which I was able to build a cross compiler successfully.

But there are more issues. In order to build Haskell bindings to Cairo, SDL2,
SDL2_mixer and Chipmunk you first need to be able to build the requisite C
libraries. This has been quite annoying so far and I can see it's going to take
me at least a week or two.

What I've decided to do is what the Chromium project supposedly does and
that is to create one giant repo which contains all the source code I need.
I'm not sure about the best way to go about this. Should I pull in the
source repos, not change them, and then apply patches during the build process
or is it okay for me make changes to specific sub-repos? What is better in the
long run?

Having a read about how Chromium does things
(http://www.chromium.org/developers/adding-3rd-party-libraries) I note the
following interesting features:

- they store the SHA512 hash of the tar ball they got the source from. For git
  it's not clear what they do but a hash of the source tree and the commit
  hash would probably be enough to uniquely identify it.

- they update the code when something is fixed upstream.

- they do license file checks.

# Fri 17 Oct 2014

## 09:30

I'd now like to work out what is remaining on the game.

1. I need to get the radii of the germs right, which I think is going
   to be a bit of a chore. The problem is that the edges of the germs are
   Bezier curves where the control points lie outside the actual
   physical edge of the curve. (The control points lie on what I'll dub the
   "notional radius" of the germs.) Unless I calculate what the outermost point
   of the germs are using Bezier maths I can't really know what the *true*
   radius of the germs is. Since the notional radius is used for collision
   detection it looks like the germs are colliding when their edges aren't
   touching. Perhaps this isn't a problem, and I can live with it. It's
   not like the collisions were ever going to be "pixel perfect".

2. I'd like to add a blur effect to the game to make it truly look like
   a petrie dish. It's going to be hard to get the performance acceptable.
   After just a little preliminary reading I don't think I just want to do
   a Guassian blur but rather to use a more sophisticated depth of field
   effect or "bokeh" effect.

3. I need to create a playground in which Rauri can make the germs look
   better.
      - Docker
      - blog posts to teach him about Haskell
      - crib the Cairo wrapper from Helm.

4. I want the antibiotics to be dragged and dropped on top of the germs
   and to have an area of effect that is not the complete screen. As the
   antibiotics get less potent they fade in colour until they become
   clear eventually.

5. I want to add squish sound effects.

6. I want to add the "Crystal Harmony" music in the background. Eventually
   I will have to get some custom music made. The piece is way too good
   for this game and goes places emotionally that don't really fit with the
   mood of the game.

## 08:50

I tried both solutions. Of course the pure Hipmunk solution worked but
ultimately I was unhappy with it. It took me a long time to get right
because I had to ensure that actions evaluated with 'unsafePerformIO'
happened in the right order. It just felt ugly.

So I decided to go with the free monad approach. I didn't write about this
before but one thing that concerned me is that I didn't just want to shove
the entire Hipmunk interface into this monad. What I really wanted was
to be able to evaluate another, smaller, Hipmunk free monad inside the
Game free monad. I didn't know this was possible before I started but
thankfully it was!

It turns out that you need to enable GADTs (or at least ExistentialTypes)
in order to have operations in your free monad that are polymorphic.
I wanted to have an operation:

    runHipM :: HipSpace -> HipM a -> GameM a

I'm lying a little about the type. In the end both the GameM monad
and the HipM monad are run inside the IO monad, but the basic idea is there.

Two data types, GameScript and HipScript are defined that are then turned
into free monads by application of the Free type constructor.

    type GameM = Free GameScript
    type HipM  = Free HipScript

The GameScript type looked a little like this:

    data GameScript next =
        Get     (GameState -> next)
      | Put     GameState next
      | forall a. RunHipM HipSpace HipM a (a -> next)

See how I needed to introduce an existential type? It turns out you'd need
it for even more mundane situations. What if you wanted to put the "read"
operation in GameScript (corresponding to read :: Read a => String -> a).
This would be encoded as:

    | forall a. Read a => Read String (a -> next)

(the first occurrence of Read is a type class name, whereas the second is
a constructor name)

Anyway, back to the matter at hand, how do we evaluation one free monad
inside another? Really it's quite easy! You just need to make sure
that the target monad of both free monad interpreters is the same.
In my case that was IO.

    runGameM :: GameState -> GameM a -> (IO a, GameState)
    runHipM :: HipSpace -> HipM a -> IO a

Then you implement the RunHipM case as:

  case gameM of
    (Impure (RunHipM space hipM cont)) ->
      do a <- runHipM space hipM
         runGameM <current state> (cont a)

# Sat 20 Sep 2014


I've become quite obsessed with keeping the GameM monad pure. The problem
is that I'm using the Hipmunk library (a Haskell binding to the Chipmunk
physics engine) and it's firmly stuck in the IO monad. I've been doing a lot
of thinking about how to resolve this issue and I've come up with two solutions,
the second one thanks to a discussion with Lyndon. (The second one involves
using a free monad if that whets your appetite.)

Let's talk about the architecture. Currently we have a mainloop, written
in SDL and running inside the IO monad. This loop takes a "game" function
which has type signature FSMState -> Event -> GameM FSMState.

The GameM monad is a state monad with random number generation
("StateT GameState (Rand StdGen) a"). I wanted very much to keep this
monad pure but I run into the snag that I want to store the current
physics engine state inside the GameState data structure. Sure, I can *store*
an IO value inside the monad, but I certainly can't evaluate it inside
the GameM monad.

My first solution to this problem is to create a pure wrapper for Hipmunk.
I've prototyped this solution, and although it uses unsafePerformIO liberally,
it works. In order to ensure that the IO actions occur in the right order
we thread a dummy state through the functions that I defined in the API
to this pure wrapper.

The second solution would be to create a giant "super monad" for the entire
game to be in -- a free monad based on a Game DSL I define. Then I'm free
to evaluate whatever the hell I want in the IO monad but without the problem
that if I *were* just in the IO monad *anything* could be happening inside it
at any point. With the Game DSL free monad I know exactly what the actions
that can be performed inside it are.

The more I think about it the more appealing a Game DSL free monad is.
This will necessitate yet another rewrite... do I go ahead with it?

I know what I'll do. I'll try both solutions in different branches of
the git repository. I'll try the pure Hipmunk solution first.


# Tue 16 Sep 2014


I'm trying to think of a good data structure for storing germs. At the moment
I've just got a list of germs. It might be okay to add new germs to the
beginning of the list, which can be done in constant time, but what about
deleting them? If I use Data.Map I'm going to need a notion of germId which
seems cumbersome. I do probably want a k-d tree or BSP tree to reduce the number
of objects I need to check for collisions with taps. Do these need an ID?

# Sunday 14 Sep 2014


Small germs need to animate faster to look like they are moving at all.
It's much more noticeable when a big germ is moving. To simulate this
I've added an extra field to the Germ data type call germCumulativeTime.
Each frame we add the duration of the frame to this cumulative time, but we
also scale it by a factor inversely proportional to the size of the germ.
In fact, it's proportional to 1/sqrt size. For some reason this just looks
right visually.

# Fri 12 Sep 2014


I'm back to animating germs. Up until now I've been returning a bunch
of higher order functions to animate various things about the germs but now
I realise that it's all going to have to be data driven if I want to
mutate the germs properly. You can't inspect functions!

I've decided that there are three inheritable characteristics of a germ
- number of spikes
- body gradient
- nucleus gradient

but I will also pre-calculate collections of so-called "moving points".
The moving points are polar points where each component also as a list of
"periodic functions" associated with it. However, these periodic functions
are represented as data. Each periodic function has amplitude, period and
phase.

# Thu 11 Sep 2014

Today I finished writing the FSM module but then deleted it, realising it
was clunky and didn't actually simplify anything. The problem was
that the finite state machine had states with associated data.
e.g. [FSMLevel Int] is on of the variants.

My FSM module essentially created an association list between FSM states
and transition functions which conditionally took us to a new FSM state.
However, what you really want to do is a pattern match against the FSM state.
e.g. case fsmState of
       FSMLevel i -> ... some code ...

Thinking about how I would rewrite my module I realised I didn't even need it.

# Wed 10 Sep 2014

In the JavaScript version of the game I created a finite state machine
that captured the essence of the game. I'd like to do that again but I want
to think carefully about it. You see, there is only a need to run at
several frames per second when the game is in the FSMLevel state, otherwise
it makes sense to pause the main loop. At present I'm pretty sure I don't
have a way to do that. If the frame updates were occurring in a separate
thread and I triggered each frame update with a very simple message then
it would be easy to stop and start it. Is this too heavy weight a solution?

Also, if I start using threads will this interact well with an iOS
backend? I seem to remember there being issues.

Let's attack this problem from the other direction. Can we pause the
frame loop if our program is just single threaded? Clearly not. If our
program is single threaded we are forced to either be in this loop or
somewhere else, and that is simply how it is.

What we really want are three threads:

1. frame loop.
2. event loop.
3. Control flow loop. Where all the game logic happens.

In the Cocoa and iOS world we have a notion of "run loops" which handle input
sources and can also have timers set on them. They are responsible for
detecting input and dispatching events.

Think from the perspective of the backend. You pass the backend
the game functions, which are essentially callbacks.

Okay, you're going to have to think carefully about architecture.

Things to do:
[ ] Get clear on what 'callback hell' is, and what the alternatives are.
[ ] Look into using STM possibly.

My suspicions about callback hell are this. You start your game loop
and you set a bunch of callbacks. Now you are in a position where
you have to think about 2 or more actors interacting with each other.
You need to make sure that race conditions don't occur where both actors
are manipulating shared memory at the same time. You cannot avoid this.
As soon as you've put callbacks into place this is a real possibility!


## 14:44

I did a little bit of study into GLUT and discovered that the callbacks are
all essentially called in sequence in a single thread. The "idle callback" is
to be used whenever user input has finished being handled. Based on this,
I'm going to go back and remove my threaded code. It required MVars to ensure
that race conditions occurred and will be a lot simpler. However, I am
going to add some more state to BackendState to track how long it takes
to a) update the game state and b) render the frame.

This way we can dynamically update the rate at which the game displays. Even
in completely pathological cases we can reduce the frame rate to once every
few seconds if it starts taking forever to render.

## 16:28

Okay, it's getting a bit ridiculous that I still haven't implemented the
state machine data structure, so I'm going to implement that right now. Then
I will come back to the issue of avoiding "death spirals" in rendering.


# Mon 08 Sep 2014

At the moment I'm checking for events (such as keypresses/mouseclicks)
on every frame. This is not really the way I should be doing it. I should
be handling the events asynchronously in a separate thread. In order not to
have a race conditions when updating the state of the game I'm going to need
to use MVars or some such mechanism.

However, I'll do this later. I've put it in the TODO file.


Things I learned today:

It is good to log information such as framerate. There was a point where
I was doing what I thought was a blocking call to wait for an SDL event
but in fact it was repeatedly polling and eating up valuable CPU cycles.
The game looked just the same to me but my logging told me differently.
It reminds me of the phenomenon pilots go through when their eyes are telling
them something different to their instruments.
