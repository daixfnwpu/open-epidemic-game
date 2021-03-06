module ProfileGraphics where

--
-- This module just profiles graphics. I hope to answer the question of whether I should
-- use one big shader or smaller shaders, as well as have a benchmark to full back to
-- any time I change the shader code.
--
-- I also hope to test this on several bits of hardware, as graphics cards vary widely.
--

import           Graphics.Rendering.OpenGL.Raw
import qualified Graphics.UI.SDL          as S
import qualified Graphics.UI.SDL.Keycode  as SK
import           Data.IORef
import           Control.Monad.Random
import           Control.Monad
import           Data.Bits
import           Data.Time

-- friends
import Types
import Game.Types
import Graphics
import Platform
import CUtil
import GraphicsGL
import Util
import FrameRateBuffer
import GraphicsGL.GLSLPrograms.SeparateShaders as Separate
import GraphicsGL.GLSLPrograms.OneBigShader as OneBig

----------------------------------------------------------------------------------------------------
data S = S { sWindow    :: S.Window
           , sGfxState  :: GfxState
           , sGerms     :: GLM [GermGL]
           , sGLContext :: S.GLContext
           , sFrames    :: Int
           , sLastTime  :: UTCTime
           , sFRBuf     :: FRBuf
           }

nGerms = 200

windowSize = 100
----------------------------------------------------------------------------------------------------
profileGraphics :: Maybe String -> IO ()
profileGraphics mbResourcePath = do
  sRef <- initialize mbResourcePath Separate.initShaders
  s <- readIORef sRef
  germGLs <- runGLMIO (sGfxState s) (sGerms s)
  mainLoop sRef germGLs justBlur

----------------------------------------------------------------------------------------------------
mainLoop :: IORef S -> a -> (GfxState -> a -> IO ()) -> IO ()
mainLoop sRef st prof = go
  where
    go :: IO ()
    go = do
      s <- readIORef sRef
      mbE <- S.pollEvent
      let quit = maybe False (checkForQuit . S.eventData) mbE
      when quit $ exitWith ExitSuccess
      ---
      prof (sGfxState s) st
      S.glSwapWindow (sWindow s)
      ---
      let frames = sFrames s
      logFramerate s
      t <- getCurrentTime
      addTick (sFRBuf s) $ realToFrac $ diffUTCTime t (sLastTime s)
      writeIORef sRef $ s { sFrames = frames + 1, sLastTime = t }
      go

----------------------------------------------------------------------------------------------------
initialize :: Maybe String -> ShadersGenerator -> IO (IORef S)
initialize mbResourcePath initShaders = do
  S.init [S.InitVideo]
  (w,h) <- case screenDimensions of
    Just (w',h') -> return (w', h')
    Nothing -> do
      mode <- S.getCurrentDisplayMode 0
      return (fromIntegral (S.displayModeWidth mode), fromIntegral (S.displayModeHeight mode))
  when (w < h) $ exitWithError $
    printf "Width of screen (%d) must be greater than or equal to height (%d)" w h
  window <- S.createWindow "Profile Graphics" (S.Position 0 0) (S.Size w h) wflags
  let glAttrs = case True of
                _ | platform `elem` [Android, IOSPlatform] ->
                       [ (S.GLDepthSize,           24)
                       , (S.GLContextProfileMask,  S.glContextProfileES)
                       , (S.GLContextMajorVersion, 2) ]
                _ -> [ (S.GLDepthSize,           24) ]
  mapM_ (uncurry S.glSetAttribute) glAttrs
  context <- S.glCreateContext window
  when (platform == MacOSX) $ S.glSetSwapInterval S.ImmediateUpdates
  resourcePath <- case platform of
    Android ->
      maybe (exitWithError "Resource path must be provided to haskell_main for Android")
            return mbResourcePath
    _ -> iOSResourcePath
  gfxState <- initGfxState (w,h) initShaders resourcePath
  let germs = replicateM 50 newGermGLM
  t <- getCurrentTime
  frBuf <- initFRBuf windowSize
  newIORef $ S { sWindow    = window
               , sGfxState  = gfxState
               , sGerms     = germs
               , sGLContext = context
               , sFrames    = 0
               , sLastTime  = t
               , sFRBuf     = frBuf
               }
  where
    wflags = [S.WindowShown] ++ (case platform of IOSPlatform -> [S.WindowBorderless]; _ -> [])

----------------------------------------------------------------------------------------------------
logFramerate :: S -> IO ()
logFramerate s = do
  when (sFrames s `mod` windowSize == 0) $ do
    avTick <- averageTick (sFRBuf s)
    debugLog $ printf "Framerate = %.2f frames/s\n" (1/avTick)


----------------------------------------------------------------------------------------------------
--
-- Just draw [nGerms] germs.
--
justGerms :: GfxState -> [GermGL] -> IO ()
justGerms gfxs _ = do
      let draw :: GermGL -> IO ()
          draw germGL = runGLMIO gfxs $ do
            germGLFun germGL 0 (R2 0 0) 0 10 1
      glBindFramebuffer gl_FRAMEBUFFER $ gfxScreenFBId gfxs
      glClearColor 1 1 1 1 -- here it must be opaque
      glClear (gl_DEPTH_BUFFER_BIT .|. gl_COLOR_BUFFER_BIT)

      -- now do the blur

----------------------------------------------------------------------------------------------------
--
-- Draw germs and then blur using a second program.
--
blurGerms :: GfxState -> [GermGL] -> IO ()
blurGerms gfxs germGLs = do
      let draw :: GermGL -> GLM ()
          draw germGL = germGLFun germGL 0 (R2 0 0) 0 10 1
          drawGerms :: GLM ()
          drawGerms = sequence_ $ map draw germGLs
      glBindFramebuffer gl_FRAMEBUFFER $ fboFrameBuffer $ gfxMainFBO gfxs
      glClearColor 1 1 1 1 -- here it must be opaque
      glClear (gl_DEPTH_BUFFER_BIT .|. gl_COLOR_BUFFER_BIT)
      let blurred :: GLM ()
          blurred = conditionalBlur (Just 1.0)
      runGLMIO gfxs $ do
        drawGerms
        blurred
----------------------------------------------------------------------------------------------------
justBlur :: GfxState -> [GermGL] -> IO ()
justBlur gfxs _ = do
      glBindFramebuffer gl_FRAMEBUFFER $ fboFrameBuffer $ gfxMainFBO gfxs
      glClearColor 1 1 1 1 -- here it must be opaque
      glClear (gl_DEPTH_BUFFER_BIT .|. gl_COLOR_BUFFER_BIT)
      let blurred :: GLM ()
          blurred = conditionalBlur (Just 1.0)
      runGLMIO gfxs $ blurred

----------------------------------------------------------------------------------------------------
checkForQuit :: S.EventData -> Bool
checkForQuit ed = case ed of
      S.Quit                    -> True
      _ | b <- isKeyDown ed SK.Q -> b

----------------------------------------------------------------------------------------------------
isKeyDown :: S.EventData -> SK.Keycode -> Bool
isKeyDown ed code = case ed of
  S.Keyboard {  S.keyMovement = S.KeyDown, S.keySym = S.Keysym _ code' _ } -> code == code'
  _ -> False

----------------------------------------------------------------------------------------------------
newGermGLM :: GLM GermGL
newGermGLM = join foo
  where
    foo :: GLM (GLM GermGL)
    foo = do
      germGfx <- liftGLM $ evalRandIO randomGermGfx
      return $ germGfxToGermGL germGfx