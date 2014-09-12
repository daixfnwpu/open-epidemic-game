module Graphics (
  -- types
  Anim, GermGfx(..), Time, Color, GermGradient, Point(..),
  -- functions
  randomGermGfx, drawGerm
) where

import Graphics.Rendering.Cairo
import Control.Monad
import Control.Monad.Random
import Control.Applicative
import Debug.Trace
-- import GameMonad
-- import Data.Foldable

{-

TODO: There is a question of whether everything is normalised or not.
Especially where we are adding periodic functions onto the radius of the germ it's sometimes
going to go out of bounds. Is this okay?

-}

-------------------------------------------
-- Constants

-- number of sin waves to sum together to produce a fairly unpredictable periodic motion
periodicsToSum :: Int
periodicsToSum = 3

jigglePeriodBounds :: (Double, Double)
jigglePeriodBounds = (7,15)

jiggleRadiusAmplitudeBounds :: (Double, Double)
jiggleRadiusAmplitudeBounds = (0.05, 0.1)

jiggleAngleAmplitudeBounds :: (Double, Double)
jiggleAngleAmplitudeBounds = (-0.02, 0.02)

jigglePhaseBounds :: (Double, Double)
jigglePhaseBounds = (0,1)

tileGermsPerRow = 10

germSpikeRange :: (Int, Int)
germSpikeRange = (5,13)

-- A value between 0 and 1 that represents how transparent the nucleus is. 0 is transparent.
-- 1 is opaque.
nucleusAlpha :: Double
nucleusAlpha = 0.5

numNucleusPoints :: Int
numNucleusPoints = 10

nucleusRadiusRange :: (Double, Double)
nucleusRadiusRange = (0.2,0.5)

-- Between 0 and 1
spikyInnerRadius, spikyOuterRadius :: Double
spikyInnerRadius = 0.5
spikyOuterRadius = 1

----------------------------------------------------------------------------------------------------
--
-- Co-ordinate systems
-- ~~~~~~~~~~~~~~~~~~~~
--
-- Internally we use type [CairoPoint]. This uses Cairo's co-ordinate system which has the origin
-- in the top-left corner, x axis goes left to right and y axis goes to bottom.
--
-- However we export a function [drawGerm] which uses the [Point] data type. THis co-ordinate
-- system is Cartesian. The origin is in the centre, the x axis goes left to right and the
-- y axis from bottom to top.
--
type Time = Double
type Anim = Time -> Render ()

data Color = Color Double Double Double Double deriving Show

type CairoPoint = (Double, Double)

-- exported
data Point = R2 Double Double

white = Color 1 1 1 1
blue  = Color 0 0 1 1
green = Color 0 1 0 1
black = Color 0 0 0 1

type GermGradient = (Color, Color)

-- polar point (r,a) that lies inside a unit circle. Invariant: r < 1, 0 <= a < 1
data PolarPoint = P2 Double Double -- radius and angle

data GermGfx =
  GermGfx { germGfxBodyGrad    :: GermGradient
          , germGfxNucleusGrad :: GermGradient
          , germGfxBody        :: [MovingPoint]
          , germGfxNucleus     :: [MovingPoint]
          , germGfxSpikes      :: Int
          }
--
-- Represents a periodic function as data.
-- \t -> pfAmp * sinU ((t + pfPhase)/pfPeriod)
--
data PeriodicFun =
  PeriodicFun { pfAmp    :: Double
              , pfPeriod :: Double
              , pfPhase  :: Double
              }

--
-- A [MovingPoint] is a polar point but each component 'r' and 'a' has been
-- annotated with a list of [PeriodicFun]s.
-- The final point at a time 't' is determined by summing the value of
-- the periodic functions at 't' and adding that to the component.
--
data MovingPoint = MP2 (Double, [PeriodicFun]) (Double, [PeriodicFun])

----------------------------------------------------------------------------------------------------
--
-- [sinU], [cosU], [tanU] are like sin, cos and tan except that they work in units of
-- "turns" (as opposed to radians or degrees). 1 turn is equal to 2*pi radians or 360 degrees.
--
-- Writing functions in terms of turns almost completely eliminates all mention of pi from
-- your functions and makes them easier to understand.
--
sinU, cosU :: Floating a => a -> a
sinU = sin . (2*pi*)
cosU = cos . (2*pi*)
tanU a = sinU a / cosU a


----------------------------------------------------------------------------------------------------
movingPtToPt :: Time -> MovingPoint -> CairoPoint
movingPtToPt t (MP2 (r, pfs) (a, pfs')) =
  polarPtToPt (P2 r' a')
  where
    r' = r + sumPeriodics t pfs
    a' = a + sumPeriodics t pfs'

----------------------------------------------------------------------------------------------------
periodicValue :: Time -> PeriodicFun -> Double
periodicValue t pf = pfAmp pf * sinU ((t + pfPhase pf)/(pfPeriod pf))


----------------------------------------------------------------------------------------------------
sumPeriodics :: Time -> [PeriodicFun] -> Double
sumPeriodics t pfs = sum . map ((/n') . periodicValue t) $ pfs
  where n = length pfs
        n' = fromIntegral n

----------------------------------------------------------------------------------------------------
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
----------------------------------------------------------------------------------------------------
--
-- Draws a germ of radius [r] centred at [(x,y)]
--
drawGerm :: GermGfx -> (Int, Int) -> Point -> Double -> Anim
drawGerm gg (w,h) (R2 x y) r t = do
  renderCenter w' h' $ do
    translate x (-y)
    scale r r
    withGermGradient (germGfxBodyGrad gg) 1 $ do
      blob . map (movingPtToPt t) . germGfxBody $ gg
    withGermGradient (pmap (changeAlpha nucleusAlpha) $ germGfxNucleusGrad gg) 1 $ do
      blob . map (movingPtToPt t) . germGfxNucleus $ gg
    -- scale to radius [r]
  where
    w' = fromIntegral w
    h' = fromIntegral h

----------------------------------------------------------------------------------------------------
withGermGradient :: GermGradient -> Double -> Render () -> Render ()
withGermGradient (Color r g b a, Color r' g' b' a') radius drawing = do
  withRadialPattern 0 0 0 0 0 radius $ \p -> do
    patternAddColorStopRGBA p 0 r  g  b  a
    patternAddColorStopRGBA p 1 r' g' b' a'
    setSource p
    drawing
    fill

----------------------------------------------------------------------------------------------------
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
radInnerCircle :: Int -> Double -> Double
radInnerCircle n r =   r*sinU (alpha n/2)

--
--
--
lenPolySide :: Int -> Double -> Double
lenPolySide    n r = 2*r*c/(1+1/2*c) where c = cosU (alpha n/2)

----------------------------------------------------------------------------------------------------
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

----------------------------------------------------------------------------------------------------
polarPtToPt :: PolarPoint -> CairoPoint
polarPtToPt (P2 r ang) = (r*cosU ang, r*sinU ang)

----------------------------------------------------------------------------------------------------
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

----------------------------------------------------------------------------------------------------
--
-- Smooths out the rough edges on a polygon
--
blob :: [CairoPoint] -> Render ()
blob ps = do
  moveTo' start
  mapM_ (uncurry quadraticCurveTo) rest
  fill
  where
    ((_,start):rest) = take (length ps + 1) . foo . cycle $ ps
    foo :: [CairoPoint] -> [(CairoPoint, CairoPoint)]
    foo []        = []
    foo [_]       = []
    foo (x:x':xs) = (x, midPt x x'):foo (x':xs)

----------------------------------------------------------------------------------------------------
midPt :: CairoPoint -> CairoPoint -> CairoPoint
midPt (x,y) (x',y') = ((x+x')/2, (y+y')/2)

----------------------------------------------------------------------------------------------------
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

----------------------------------------------------------------------------------------------------
circle :: CairoPoint -> Double -> Render ()
circle (x,y) r = arc x y r 0 (2*pi)

----------------------------------------------------------------------------------------------------
polygon :: [CairoPoint] -> Render ()
polygon []  = return ()
polygon [_] = return ()
polygon (s:x:xs) = moveTo' s >> go (x:xs)
  where
    go []     = lineTo' s
    go (x:xs) = lineTo' x >> go xs


----------------------------------------------------------------------------------------------------
moveTo', lineTo' :: (Double, Double) -> Render ()
moveTo' = uncurry moveTo
lineTo' = uncurry lineTo

----------------------------------------------------------------------------------------------------
setColor :: Color -> Render ()
setColor (Color r g b a) = setSourceRGBA r g b a

----------------------------------------------------------------------------------------------------
inContext :: Render () -> Render ()
inContext r = save >> r >> restore

----------------------------------------------------------------------------------------------------
withColor :: Color -> Render () -> Render ()
withColor color d = inContext $ setColor color >> d

----------------------------------------------------------------------------------------------------
quadraticCurveTo :: CairoPoint -> CairoPoint -> Render ()
quadraticCurveTo (cx,cy) (ex,ey) = do
   (x,y) <- getCurrentPoint
   curveTo (f x cx) (f y cy) (f ex cx) (f ey cy) ex ey
   where
     f a b = 1.0/3.0 * a + 2.0/3.0 * b

----------------------------------------------------------------------------------------------------
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

----------------------------------------------------------------------------------------------------
-- Randomness

randomColor :: RandomGen g => Rand g Color
randomColor = do
  (r:g:b:_)  <- getRandomRs (0, 1)
  return $ Color r g b 1

----------------------------------------------------------------------------------------------------
--
-- Like mod but for RealFrac's
--
fmod :: RealFrac a => a -> a -> a
fmod a b = snd (properFraction (a / b)) * b

----------------------------------------------------------------------------------------------------
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

----------------------------------------------------------------------------------------------------
randomGermGfx :: RandomGen g => Rand g GermGfx
randomGermGfx = do
  n <- getRandomR germSpikeRange
  g <- randomGradient
  g' <- randomGradient
  let bodyPts = starPolyPoints n spikyInnerRadius spikyOuterRadius
  bodyPts'    <- mapM polarPtToMovingPt bodyPts
  nucleusPts  <- randomRadialPoints2 numNucleusPoints
  nucleusPts' <- mapM polarPtToMovingPt nucleusPts
  return $ GermGfx
    { germGfxBodyGrad    = g
    , germGfxNucleusGrad = g'
    , germGfxBody        = bodyPts'
    , germGfxNucleus     = nucleusPts'
    , germGfxSpikes      = n }
  where

----------------------------------------------------------------------------------------------------
randomRadialPoints2 :: RandomGen g => Int -> Rand g [PolarPoint]
randomRadialPoints2 n = do
  rs <- getRandomRs nucleusRadiusRange
  let as = [0, 1/n'..1-1/n']
  return $ zipWith P2 rs as
  where
    n' = fromIntegral n

----------------------------------------------------------------------------------------------------
randomPeriodicFuns :: RandomGen g => (Double, Double) -> Rand g [PeriodicFun]
randomPeriodicFuns ampBounds = do
  amps    <- getRandomRs ampBounds
  periods <- getRandomRs jigglePeriodBounds
  phases  <- getRandomRs jigglePhaseBounds
  let pFuns   = zipWith3 PeriodicFun amps periods phases
  return $ take periodicsToSum $ pFuns

----------------------------------------------------------------------------------------------------
polarPtToMovingPt :: RandomGen g => PolarPoint -> Rand g MovingPoint
polarPtToMovingPt (P2 r a) = do
  pfs <- randomPeriodicFuns jiggleRadiusAmplitudeBounds
  pfs' <- randomPeriodicFuns jiggleAngleAmplitudeBounds
  return $ MP2 (r, pfs) (a, pfs')

----------------------------------------------------------------------------------------------------
changeAlpha :: Double -> Color -> Color
changeAlpha a' (Color r g b a) = Color r g b a'

----------------------------------------------------------------------------------------------------
-- map over uniform pairs. Would be better to use a new data structure [data Pair a = Pair a a]
pmap :: (a -> b) -> (a,a) -> (b,b)
pmap f (a,b) = (f a, f b)


----------------------------------------------------------------------------------------------------
--
-- Produces n*n germs on a wxh screen
--
tiledGerms :: RandomGen g => Int -> Int -> Int -> Rand g Anim
tiledGerms n w h = do
  germs <- replicateM (n*n) randomGermGfx
  let germsAndCentres = zip germs centres
  return $ \t -> do
    forM_ germsAndCentres $ \(g, (x,y)) -> do
      drawGerm g (w,h) (R2 x y) r t

  where
    n'      = fromIntegral n
    r       = fromIntegral (min w h) / (n'*2)
    vs      = [r,3*r..n'*2*r-1]
    centres = [ (x,y) | x <- vs, y <- vs]

----------------------------------------------------------------------------------------------------
asGroup :: Render () -> Render ()
asGroup r = do
  pushGroup
  r
  popGroupToSource
  paint

----------------------------------------------------------------------------------------------------
newSingleGermAnim :: RandomGen g => (Int, Int) -> Rand g Anim
newSingleGermAnim (screenWidth, screenHeight) = do
  let w = fromIntegral screenWidth
      h = fromIntegral screenHeight
      r = (min w h) / 2 :: Double
  g <- randomGermGfx
  return $ \t -> do
    renderCenter w h  $ drawGerm g (screenWidth,screenHeight) (R2 0 0) r t

----------------------------------------------------------------------------------------------------
newGermAnim :: RandomGen g => (Int,Int) -> Rand g Anim
newGermAnim (screenWidth, screenHeight) =
  tiledGerms tileGermsPerRow screenWidth screenHeight