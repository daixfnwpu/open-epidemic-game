module Graphics where

import Graphics.Rendering.Cairo
import Control.Monad
import Control.Monad.Random
import Control.Applicative
import Debug.Trace
-- import GameMonad
-- import Data.Foldable

-------------------------------------------
-- Constants

-- number of sin waves to sum together to produce a fairly unpredictable periodic motion
periodicsToSum :: Int
periodicsToSum = 3

jigglePeriodBounds :: (Double, Double)
jigglePeriodBounds = (7,15)

tileGermsPerRow = 10
-------------------------------------------

sinU, cosU :: Floating a => a -> a
sinU = sin . (2*pi*)
cosU = cos . (2*pi*)
tanU a = sinU a / cosU a

type Time = Double
type Anim = Time -> Render ()

data Color = Color Double Double Double Double deriving Show

type Point = (Double, Double)

white = Color 1 1 1 1
blue  = Color 0 0 1 1
green = Color 0 1 0 1
black = Color 0 0 0 1

type GermGradient = (Color, Color)

data GermKind = Wobble Int -- number of wobbles
              | Spiky  Int -- number of spikes
              deriving Show

-- point which lies inside a unit circle. Invariant: x*x + y*y < 1
newtype NormalisedPoint = NormalisedPoint Point deriving Show

data GermGfx = GermGfx { germBody         :: Double -> Anim -- function from radius to animation
                       , germRadius       :: Double
                       , germBodyGrad     :: GermGradient
                       , germNucleusGrad  :: GermGradient
                       , germNucleusPts   :: Time -> [NormalisedPoint]
                       }

renderOnWhite :: Int -> Int -> Render () -> Render ()
renderOnWhite w h drawing = do
  setAntialias AntialiasSubpixel
  drawBackground
  asGroup drawing
  where
    drawBackground = do
      setColor white
      rectangle 0 0 (fromIntegral w) (fromIntegral h)
      fill

normalisedPtToPt :: Double -> NormalisedPoint -> Point
normalisedPtToPt scale (NormalisedPoint (x,y)) = (scale*x, scale*y)

drawGerm :: GermGfx -> Anim
drawGerm g t = do
  let r = germRadius g
  withGermGradient (germBodyGrad g) r    $ germBody g r t
  withGermGradient (germNucleusGrad g) r $ blob (map (normalisedPtToPt (r/2)) $ germNucleusPts g t)

withGermGradient :: GermGradient -> Double -> Render () -> Render ()
withGermGradient (Color r g b a, Color r' g' b' a') radius drawing = do
  withRadialPattern 0 0 0 0 0 radius $ \p -> do
    patternAddColorStopRGBA p 0 r  g  b  a
    patternAddColorStopRGBA p 1 r' g' b' a'
    setSource p
    drawing
    fill

-- TODO: Draw some pictures of how you derived radCircle and lenPolySide
wobble :: Int -> Double -> Render ()
wobble bumpiness radius = do
  let radial s a = (s*cosU a, s*sinU a)
      l          = lenPolySide bumpiness radius
      r          = radius - l/4
      evenPts    = map (radial (radius - l/4))     [0,2/bumps..1]
      oddPts     = map (radial (radInnerCircle bumpiness r)) [1/bumps,3/bumps..1]
      smallCircle pt = circle pt (l/4) >> fill
  mapM_ smallCircle evenPts
  polygon evenPts >> fill
  mapM_ (clear . smallCircle) oddPts
    where
      bumps = fromIntegral (2*bumpiness)

--
-- Take a circle of radius [r], transcribe a regular polygon with [n] sides
-- inside it. Each vertex touches the circle at regular intervals. Now transcribe
-- a circle within that polygon. The circle will touch the mid-point of each side
-- of the polygon.
--
-- This function returns radius of that inner circle.
--
radInnerCircle n r =   r*sinU (alpha n/2)

--
--
--
lenPolySide    n r = 2*r*c/(1+1/2*c) where c = cosU (alpha n/2)

--
-- Takes two lists, not necessarily of the same length.
-- Returns a list that alternates between elements of the
-- first list and the second list up to the point where
-- the shorter list runs out of values. The remaning elements
-- are from the longer list.
--
-- Examples:
--
-- alternate [1,2]     [10,20]     == [1,10,2,20]
-- alternate [1,2]     [10,20,30]  == [1,10,2,20,30]
-- alternate [1,2,3,4] [10,20]     == [1,10,2,20,3,4]
--
alternate :: [a] -> [a] -> [a]
alternate [] ys = ys
alternate xs [] = xs
alternate (x:xs) (y:ys) = x:y:alternate xs ys

data PolarPoint = P2 Double Double -- radius and angle

polarPtToPt :: PolarPoint -> Point
polarPtToPt (P2 r ang) = (r*cosU ang, r*sinU ang)

--
-- Given [n] the number of points in the star, and two value specifying
-- the inner and out radii, returns the points defining a star.
-- The first "point" of the star points right.
--
starPolyPoints :: Int -> Double -> Double -> [PolarPoint]
starPolyPoints n ri ro = polarPoints
  where
    n' = fromIntegral n
    angInc = 1/n' -- angle between points on star
    outerPolarPt a = P2 ro a
    innerPolarPt a = P2 ri (a + angInc/2)
    polarPoints =  [f a | a <- angles, f <-  [outerPolarPt, innerPolarPt]]
    angles = [0,angInc..1-angInc]

--
-- Smooths out the rough edges on a polygon
--
blob :: [Point] -> Render ()
blob ps = do
  moveTo' start
  mapM_ (uncurry quadraticCurveTo) rest
  fill
  where
    ((_,start):rest) = take (length ps + 1) . foo . cycle $ ps
    foo :: [Point] -> [(Point, Point)]
    foo []        = []
    foo [_]       = []
    foo (x:x':xs) = (x, midPt x x'):foo (x':xs)

spikyAnim :: RandomGen g => Int -> Rand g (Double -> Anim)
spikyAnim n = do
  drs <- replicateM (2*n) $ randomPeriodicSum (0.05,0.1)   jigglePeriodBounds (0,1)
  das <- replicateM (2*n) $ randomPeriodicSum (-0.02,0.02) jigglePeriodBounds (0,1)
  return $ \r t ->
    let polarPts = zipWith (f t) ds (starPolyPoints n r (r/2))
        drs'     = map ((*r)<$>) drs -- scale all by 'r'
        ds       = zip drs' das
    in  blob . map polarPtToPt $ polarPts
  where
    f t (dr, ar) (P2 r a) = P2 (r + dr t) (a + ar t)

starPolyPointsAnim :: RandomGen g => Int -> Rand g (Double -> Time -> [Point])
starPolyPointsAnim n = do
  return $ \r t -> map polarPtToPt $ starPolyPoints n r (r/2)


midPt :: Point -> Point -> Point
midPt (x,y) (x',y') = ((x+x')/2, (y+y')/2)

--
-- alpha returns the internal angle of a regular n-gon in turns
--
alpha :: (Integral a, Fractional f) => a -> f
alpha n = (n'-2)/(2*n') where n' = fromIntegral n

-------------------------------------------------
-- Random helpers to make Cairo more declarative

clear :: Render () -> Render ()
clear r = inContext $ do
  setOperator OperatorClear
  r

circle :: Point -> Double -> Render ()
circle (x,y) r = arc x y r 0 (2*pi)

polygon :: [Point] -> Render ()
polygon []  = return ()
polygon [_] = return ()
polygon (s:x:xs) = moveTo' s >> go (x:xs)
  where
    go []     = lineTo' s
    go (x:xs) = lineTo' x >> go xs


moveTo' = uncurry moveTo
lineTo' = uncurry lineTo

setColor :: Color -> Render ()
setColor (Color r g b a) = setSourceRGBA r g b a

inContext :: Render () -> Render ()
inContext r = save >> r >> restore

withColor :: Color -> Render () -> Render ()
withColor color d = inContext $ setColor color >> d

quadraticCurveTo :: Point -> Point -> Render ()
quadraticCurveTo (cx,cy) (ex,ey) = do
   (x,y) <- getCurrentPoint
   curveTo (f x cx) (f y cy) (f ex cx) (f ey cy) ex ey
   where
     f a b = 1.0/3.0 * a + 2.0/3.0 * b

---------------------------------------
-- Randomness

randomColor :: RandomGen g => Rand g Color
randomColor = do
  (r:g:b:_)  <- getRandomRs (0, 1)
  return $ Color r g b 1

--
-- mag:    any value
-- period: in seconds
-- phase:  between 0 and 1
--
--
periodic :: Floating a => a -> a -> a -> a -> a
periodic mag period phase t = mag * sinU ((t+phase)/period)

--
-- Like mod but for RealFrac's
--
fmod :: RealFrac a => a -> a -> a
fmod a b = snd (properFraction (a / b)) * b

-----------------------

-- TODO: Make sure that the blob pulsates between 0 and 1
--
-- Given [n] and number of points and bounds [(lo, hi)] produces a series
-- of points. Angularly they are equal spaced around the origin. Their
-- radii differ though.
--
randomRadialPoints :: RandomGen g => Int -> Rand g (Time -> [NormalisedPoint])
randomRadialPoints n = do
  rs            <- getRandomRs (0.5,0.7)
  periodicFs    <- replicateM n $ randomPeriodicSum (0.1,0.3) jigglePeriodBounds (0,1)
  let as         = [0,1/n'..1-1/n']
      movingRs t = zipWith (f t) periodicFs rs
  return $ \t -> map (NormalisedPoint . polarPtToPt) $ zipWith P2 (movingRs t) as
  where
    n'              = fromIntegral n
    f t periodicF r = r + periodicF t

--
-- Returns a periodic function that is a sum of several sin waves
-- (for added randomness)
--
randomPeriodicSum :: (RandomGen g, Random a, Floating a) => (a,a) -> (a,a) -> (a,a)
                  -> Rand g (a -> a)
randomPeriodicSum magBounds periodBounds phaseBounds = do
  -- we are summing [periodicstoSum] magnitudes together so we have to divide each
  -- by [periodicsToSum] to ensure min/max magnitude is in magBounds
  mags    <- getRandomRs $ pmap (/fromIntegral periodicsToSum) magBounds
  periods <- getRandomRs periodBounds
  phases  <- getRandomRs phaseBounds
  return $ foldl1 (liftA2 (+)) $ take periodicsToSum $ periodic <$> mags <*> periods <*> phases

-- The infinite list of [randomPeriodicSum]s
randomPeriodicSums :: (RandomGen g, Random a, Floating a) => (a,a) -> (a,a) -> (a,a)
                   -> Rand g [a -> a]
randomPeriodicSums a b c = sequence . repeat $ randomPeriodicSum a b c

randomPeriodicSumsN :: (RandomGen g, Random a, Floating a) => Int -> (a,a) -> (a,a) -> (a,a)
                   -> Rand g [a -> a]
randomPeriodicSumsN 0 _ _ _ = return []
randomPeriodicSumsN n a b c = do
  p <- randomPeriodicSum a b c
  ps <- randomPeriodicSumsN (n-1) a b c
  return (p:ps)


--
-- We want the two colours to be a minimum distance apart
--
--
randomGradient :: RandomGen g => Rand g GermGradient
randomGradient = do
  c@(Color r g b _) <- randomColor
  (dr:dg:db:_)   <- getRandomRs (0.1,0.5)
  return (c, Color (f r dr) (f g dg) (f b db) 1)
  where
    f x dx = if x < 0.5 then x + dx else x - dx

randomGerm :: RandomGen g => Double -> Rand g GermGfx
randomGerm radius = do
  n      <- getRandomR (5,13)
  body   <- spikyAnim n
  g      <- randomGradient
  g'     <- pmap (changeAlpha 0.5) <$> randomGradient
  pts    <- randomRadialPoints 7
  return $ GermGfx body radius g g' pts

changeAlpha :: Double -> Color -> Color
changeAlpha a' (Color r g b a) = Color r g b a'

-- map over uniform pairs. Would be better to use a new data structure [data Pair a = Pair a a]
pmap :: (a -> b) -> (a,a) -> (b,b)
pmap f (a,b) = (f a, f b)

--------------------------

--
-- Produces n*n germs on a wxh screen
--
tiledGerms :: RandomGen g => Int -> Int -> Int -> Rand g Anim
tiledGerms n w h = do
  germs <- replicateM (n*n) (randomGerm r)
  let germsAndCentres = zip germs centres
  return $ \t -> do
    forM_ germsAndCentres $ \(g, (x,y)) -> do
      save
      translate x y
      drawGerm g t
      restore
  where
    n'      = fromIntegral n
    r       = fromIntegral (min w h) / (n'*2)
    vs      = [r,3*r..n'*2*r-1]
    centres = [ (x,y) | x <- vs, y <- vs]

asGroup :: Render () -> Render ()
asGroup r = do
  pushGroup
  r
  popGroupToSource
  paint

renderCenter :: Double -> Double -> Render () -> Render ()
renderCenter w h drawing = do
  setAntialias AntialiasSubpixel
  drawBackground
  translate (w/2) (h/2)
  asGroup drawing
  where
    drawBackground = do
      setColor white
      rectangle 0 0 w h
      fill

newSingleGermAnim :: RandomGen g => (Int, Int) -> Rand g Anim
newSingleGermAnim (screenWidth, screenHeight) = do
  let w = fromIntegral screenWidth
      h = fromIntegral screenHeight
  g <- randomGerm (fromIntegral (min screenWidth screenHeight) / 2)
  return $ \t -> do
    translate (w/2) (h/2)
    drawGerm g t

newGermAnim :: RandomGen g => (Int,Int) -> Rand g Anim
newGermAnim (screenWidth, screenHeight) =
  tiledGerms tileGermsPerRow screenWidth screenHeight