{-# LANGUAGE GADTs, LiberalTypeSynonyms #-}
module Game where

--
-- This module will contain all the game mechanics but will not concern itself
-- with issues of rendering.
--

-- system imports
import           Control.Monad.Random hiding (getRandom, evalRand)
import           Control.Monad (replicateM)
import           Control.Applicative
import           Text.Printf
import qualified Data.Map as M
import           Data.Map (Map)
import           Control.Monad (filterM, when)
import           Data.Maybe (catMaybes, isJust, fromJust)

-- friends
import Types
import GameEvent
import GameM
import Graphics   -- vector graphics
import GraphicsGL -- GL graphics
import Util

----------------------------------------------------------------------------------------------------
--
-- Given an initial size [initSize] and a time that the germ should multiply at [multiplyAt]
-- (now being twice its original size) returns a function that given a time [t] returns
-- the current germ size.
--
--
germSizeFunForParams :: Double -> Double -> (Time -> Double)
germSizeFunForParams initSize multiplyAt t = initSize * (2**(t/multiplyAt))

----------------------------------------------------------------------------------------------------
birthGerm :: Germ -> Double -> HipCirc -> GameM Germ
birthGerm g = generateGerm $ Just g

----------------------------------------------------------------------------------------------------
createGerm :: Double -> HipCirc -> GameM Germ
createGerm = generateGerm Nothing

----------------------------------------------------------------------------------------------------
--
-- [generateGerm] either creates a germ from scratch (when you pass it [Nothing]) as the first
-- argument or creates a mutated germ that inherents from [Just germ] (if you pass it as the first
-- argument)
--
generateGerm :: Maybe Germ -> Double -> HipCirc -> GameM Germ
generateGerm mbGerm initSize hipCirc = do
  gs              <- get
  gfx <- evalRand $ case mbGerm of
           Just germ -> mutateGermGfx (germGfx germ)
           Nothing   -> randomGermGfx
  multiplyAt      <- evalRand $ randomValWithVariance doublingPeriod  doublingPeriodVariance
  germGL          <- runGLM $ germGfxToGermGL gfx
  germResistances <-
    case mbGerm of
      Just g  -> return $ germResistances g
      Nothing -> evalRand $ randomGermResistances $ gsAntibiotics gs
  return $ Germ { germMultiplyAt     = multiplyAt
                , germSizeFun        = germSizeFunForParams initSize multiplyAt
                , germHipCirc        = hipCirc
                , germGfx            = gfx
                , germGL             = germGL
                , germCumulativeTime = 0
                , germAnimTime       = 0
                , germSelected       = False
                , germResistances    = germResistances
                }
----------------------------------------------------------------------------------------------------
randomValWithVariance :: RandomGen g => Double -> Double -> Rand g Double
randomValWithVariance val variance = (val+) <$> getRandomR (-variance, variance)

----------------------------------------------------------------------------------------------------

randomGermResistances :: RandomGen g => Map Antibiotic AntibioticData -> Rand g [Antibiotic]
randomGermResistances m = catMaybes <$> (mapM immunity $ M.toList m)
  where
    immunity :: RandomGen g => (Antibiotic, AntibioticData) -> Rand g (Maybe Antibiotic)
    immunity (ab, abd) = do
      let immunityChance = 1 - abEffectiveness abd
      d <- getRandomR (0, 1)
      return $ if d <= immunityChance then Just ab else Nothing

----------------------------------------------------------------------------------------------------
--
-- Finite State Machine states for this game.
--
data FSMState = FSMLevel              Int -- level number
              | FSMPlayingLevel
              | FSMAntibioticUnlocked UTCTime Antibiotic
              | FSMLevelComplete      UTCTime
              | FSMGameOver           UTCTime
              deriving (Show, Eq, Ord)


----------------------------------------------------------------------------------------------------
--
-- The sorts of events that can occur are dependent on the state of the FSM.
--
-- FIXME: Remove the need for this IO function.
--
newGameState :: (Int, Int) -> IO GameState
newGameState bounds = do
  return $ initGameState bounds (error "Hipmunk space not defined yet") []

resetGameState :: GameM ()
resetGameState = do
  gs <- get
  hipSpace <- newHipSpace
  addBoundsToHipSpace hipSpace
  put $ initGameState (gsBounds gs) hipSpace []

resetHipState :: GameM ()
resetHipState = do
  hipSpace <- newHipSpace
  addBoundsToHipSpace hipSpace
  modify $ \gs -> gs { gsHipState = hipSpace }



addBoundsToHipSpace :: HipSpace -> GameM ()
addBoundsToHipSpace hipSpace = runHipM hipSpace $ do
  -- bottom
  addHipStaticPoly [R2 (-w) (-h), R2 w (-h), R2 w (-h - d), R2 (-w) (-h - d)]
  -- top
  addHipStaticPoly [R2 (-w) (h+d), R2 w (h+d), R2 w h, R2 (-w) h]
  -- left
  addHipStaticPoly [R2 (-w-d) (-h), R2 (-w-d) h, R2 (-w) h, R2 (-w) (-h)]
  -- right
  addHipStaticPoly [R2 (w) (-h), R2 (w) h, R2 (w+d) h, R2 (w+d) (-h)]
  where
    w = fieldWidth/2
    h = fieldHeight/2
    d  = 0.2 * w

initGameState :: (Int,Int) -> HipSpace -> [Germ] -> GameState
initGameState bounds hipSpace germs =
  GameState {
      gsRender        = (return ())
    , gsBounds        = bounds
    , gsGerms         = germMapList
    , gsNextGermId    = (length germs)
    , gsHipState      = hipSpace
    , gsSoundQueue    = []
    , gsCurrentLevel  = 1 -- current level
    , gsAntibiotics   = M.fromList $ map initAntibiotic $ allAntibiotics
    , gsScore         = 0
    }
  where
    germMapList = M.fromList $ zip [0..] germs
    initAntibiotic ab =
      let dy = (sideBarTop - sideBarBottom) / (fromIntegral n)
          n  = numAntibiotics + 1
          abN = fromIntegral (fromEnum ab + 1)
          pos = R2 (sideBarLeft + sideBarWidth/2) (sideBarTop - (abN * dy))
      in (ab, AntibioticData { abEffectiveness = startingAntibioticEffectiveness
                             , abEnabled       = False
                             , abInitPos       = pos
                             , abPos           = pos
                             , abSelected      = False
                              })

----------------------------------------------------------------------------------------------------
--
-- The game as a Finite State Machine
--
handleEvent :: FSMState -> Event -> GameM FSMState
handleEvent fsmState ev = do
  -- events that can occur in any FSM State
  case ev of
    Reset  -> resetGameState >> (return $ FSMLevel startLevelGerms)
    _  -> (case fsmState of -- events that depend on current FSM State
             FSMLevel i                 -> fsmLevel i
             FSMPlayingLevel            -> fsmPlayingLevel
             FSMAntibioticUnlocked t ab -> fsmAntibioticUnlocked (t,ab)
             FSMLevelComplete      t    -> fsmLevelComplete t
             FSMGameOver           t    -> fsmGameOver t)
  where
    fsmLevel i = do
      resetHipState
      -- create [n] germs randomly
      germs <- replicateM i $ do
                 x <- getRandom (-fieldWidth/8, fieldWidth/8)
                 y <- getRandom (-fieldHeight/8, fieldHeight/8)
                 initSize <- evalRand $ randomValWithVariance initialGermSize initialGermSizeVariance
                 hc <- runOnHipState $ addHipCirc initSize (R2 x y)
                 createGerm initSize hc
      modify $ \gs -> gs { gsGerms        = M.fromList (zip [0..] germs)
                         , gsNextGermId   = length germs
                         , gsSoundQueue   = [GameSoundLevelMusicStart]
                         , gsCurrentLevel = i
                         }
      -- FIXME: Remove. Penicillin should not be enabled initially.
      return $ FSMPlayingLevel
    --------------------------------------
    fsmPlayingLevel :: GameM FSMState
    fsmPlayingLevel = do
      gs <- get
      if M.size (gsGerms gs) > maxGerms
       then do { t <- getTime; return $ FSMGameOver t }
       else do
        case ev of
          Tap p            -> playingLevelTap p
          Select p         -> playingLevelSelect p
          Unselect p       -> playingLevelUnselect p
          Drag p p'        -> playingLevelDrag p p'
          Physics duration -> do
            physics duration
            return fsmState
          _ -> return fsmState -- error $ printf "Event '%s' not handled by fsmLevel" (show ev)
    --------------------------------------
    fsmAntibioticUnlocked :: (UTCTime, Antibiotic) -> GameM FSMState
    fsmAntibioticUnlocked (t,ab) = do
      let unlockedMsg = do
            clearRender
            gameFieldRender
            addRender $ drawTextLinesOfWidth_ black (R2 0 0) fieldWidth
                            [ printf "You unlocked %s!" (show ab)
                            , ""
                            , "Some germs are immune."
                            , "Germs inherit immunity from"
                            , "their parents"
                            , ""
                            , "Careful! Each time you"
                            , "use an antibiotic"
                            , "the chance of germ"
                            , "immunity increases!" ]
            sideBarRender
            return $ FSMAntibioticUnlocked t ab
      whenEventsMutedOtherwise t unlockedMsg $ do
        case ev of
          _ | isContinue ev -> do
            --
            -- There's a small chance that the antibiotic was unlocked while killing the last
            -- germ
            --
            gs <- get
            t <- getTime
            return $ if M.size (gsGerms gs) == 0 then FSMLevelComplete t else FSMPlayingLevel
          _                 -> unlockedMsg *>> tapToContinue

    --------------------------------------
    fsmLevelComplete :: UTCTime -> GameM FSMState
    fsmLevelComplete t    = do
      gs <- get
      let levelCompleteMsg = do
            let textRender = drawTextOfWidth_ levelCompleteGrad (R2 0 0) fieldWidth
                               "Cured!"
            clearRender
            sideBarRender
            addRender textRender
            return $ FSMLevelComplete t
      whenEventsMutedOtherwise t levelCompleteMsg $ do
        case ev of
          _ | isContinue ev -> return $ FSMLevel (gsCurrentLevel gs + 1)
          _                 -> levelCompleteMsg *>> tapToContinue
    --------------------------------------
    fsmGameOver :: UTCTime -> GameM FSMState
    fsmGameOver t         = do
      let infectedMsg = do
            modify $ \gs ->
              gs { gsRender = do
                     gsRender gs -- draw what we had before
                     drawTextOfWidth_ gameOverGrad (R2 0 0) fieldWidth "Infected!"
                 , gsSoundQueue = [GameSoundLevelMusicStop]
                 }
            return $ FSMGameOver t

      whenEventsMutedOtherwise t infectedMsg $ do
        case ev of
          _ | isContinue ev -> do
            resetGameState
            return $ FSMLevel startLevelGerms
          _ -> infectedMsg *>> tapToContinue

tapToContinue :: GameM ()
tapToContinue = addRender $ drawTextOfWidth_ continueGrad (R2 0 (-worldHeight/5)) (fieldWidth/2)
                  "Tap to continue"

----------------------------------------------------------------------------------------------------
isContinue :: Event -> Bool
isContinue s = case s of
  Tap _    -> True
  Select _ -> True
  _        -> False

----------------------------------------------------------------------------------------------------
playingLevelTap ::  R2 -> GameM FSMState
playingLevelTap p = do
  germKilled <- killGerm p
  applyAntibiotics p
  gs <- get
  mbAB <- antibioticUnlocked
  case True of
    _ | germKilled && isJust mbAB -> do
          t <- getTime
          let ab = fromJust mbAB
          enableAntibiotic ab
          return $ FSMAntibioticUnlocked t ab
    _ | M.size (gsGerms gs) == 0 -> do
          t <- getTime
          return $ FSMLevelComplete t
    _  -> return FSMPlayingLevel

----------------------------------------------------------------------------------------------------
antibioticUnlocked :: GameM (Maybe Antibiotic)
antibioticUnlocked = do
  gs <- get
  return $ M.lookup (gsScore gs) unlockAntibioticsMap

----------------------------------------------------------------------------------------------------
--
-- FIXME: Make this more efficient. Brute force searches through germs to kill them.
--
killGerm :: R2 -> GameM Bool
killGerm p = do
  germsToKill <- germsSatisfyingM (pointCollides p)
  let kkk (germId, germ) = do
        gs <- get
        runOnHipState $ removeHipCirc (germHipCirc germ)
        let germs    = gsGerms gs
            newGerms = M.delete germId germs
        modify $ \gs -> gs { gsGerms = M.delete germId (gsGerms gs)
                           , gsSoundQueue = GameSoundSquish:gsSoundQueue gs
                           , gsScore = gsScore gs + 1 }
        runGLM . germGLFinaliser . germGL $ germ
        return $ M.size newGerms < M.size germs
  bs <- mapM kkk germsToKill
  return $ any id bs -- were any germs killed?

----------------------------------------------------------------------------------------------------
applyAntibiotics :: R2 -> GameM ()
applyAntibiotics (R2 x y)= do
  gs <- get
  let abClicked abd =
        let R2 x' y' = abPos abd
            w        = antibioticWidth
        in x >= x' - w/2 && x <= x' + w/2 && y >= y' - w/2 && y <= y' + w/2 &&
           abEnabled abd
      killWithAB ab gs = M.filter (\g -> ab `elem` germResistances g) (gsGerms gs)
  case (M.toList . M.filter abClicked $ gsAntibiotics gs) of
    []         -> return ()
    (ab,_):_ -> do
      let germs' = killWithAB ab gs
      modify $ \gs -> gs { gsGerms      = germs'
                         , gsSoundQueue = GameSoundSquish:gsSoundQueue gs }
      modifyAntibioticEffectiveness (effectivenessDilutionFactor*) ab

----------------------------------------------------------------------------------------------------
pointCollides :: R2 -> Germ -> GameM Bool
pointCollides (R2 x y) g = do
  let sz   = germSizeFun g (germCumulativeTime g)
  R2 x' y' <- runOnHipState $ getHipCircPos (germHipCirc g)
  return $ (x' - x)**2 + (y' - y)**2 < sz*sz
----------------------------------------------------------------------------------------------------
--
-- As mentioned above, the [germCumulativeTime] grows inversely proportional to
-- the size of the germ. I found that visually it works better if it grows as (1 / sqrt size)
-- but I have yet to determine why this looks so natural.
--
-- I have a suspicion that it has something to do with the area of the germ. To put it another way
-- small things move faster when their area is small.
--
growGerm :: Time -> GermId -> GameM ()
growGerm duration germId = do
  whenGerm germId $ \gs g -> do
    let animT  = germAnimTime g
        t      = germCumulativeTime g
        hc     = germHipCirc g
        sz     = germSizeFun g t
    -- New pos of germ from physics engine
    (R2 x y) <- runOnHipState $ getHipCircPos hc
    if (t > germMultiplyAt g)
    then do
      -- TODO mutate the germ
      dx <- getRandom (0,sz)
      dy <- getRandom (0,sz)
      let i       = gsNextGermId gs
          hc      = germHipCirc g
          (x',y') = (x + dx, y + dy)
      hc' <- runOnHipState $ do
        setHipCircRadius hc (sz/2)
        addHipCirc (sz/2) (R2 x' y')
      ng <- birthGerm g (sz/2) hc'
      insertGerm i ng -- insert new germ
      -- update first germ
      insertGerm germId $ g { germCumulativeTime = 0 }
      modify $ \gs -> gs { gsNextGermId = i + 1 }
    else do
      runOnHipState $ setHipCircRadius hc sz -- update the size in the physics
      let g' = g { germCumulativeTime = duration + t
                 , germAnimTime       = (sqrt (fieldHeight / sz) * duration) + animT }
      insertGerm germId g'

----------------------------------------------------------------------------------------------------
--
-- [whenGerm] applies [f] if germ with [germId] exists in the [GameState]
--
whenGerm :: GermId -> (GameState -> Germ -> GameM ()) -> GameM ()
whenGerm germId f = do
  gs <- get
  case M.lookup germId (gsGerms gs) of
    Just germ -> f gs germ
    Nothing   -> return ()

----------------------------------------------------------------------------------------------------
insertGerm :: GermId -> Germ -> GameM ()
insertGerm germId germ = modify $ \gs -> gs { gsGerms = M.insert germId germ (gsGerms gs) }

----------------------------------------------------------------------------------------------------
updateGerm :: (Germ -> Germ) -> (GermId, Germ) -> GameM ()
updateGerm upd (germId, g) = insertGerm germId (upd g)

----------------------------------------------------------------------------------------------------
updateGermWithId :: (a -> Germ -> Germ) -> (GermId, a) -> GameM ()
updateGermWithId f (germId, val) = do
  gs <- get
  let germs = gsGerms gs
  case M.lookup germId germs of
    Just germ -> insertGerm germId (f val germ)
    Nothing -> return ()

----------------------------------------------------------------------------------------------------
germsSatisfying :: (Germ -> Bool) -> GameM [(GermId, Germ)]
germsSatisfying f = do
  gs<- get
  return . M.toList . M.filter f $ gsGerms gs

----------------------------------------------------------------------------------------------------
germsSatisfyingM :: (Germ -> GameM Bool) -> GameM [(GermId, Germ)]
germsSatisfyingM f = do
  gs <- get
  let germPs = M.toList $ gsGerms gs
      f' :: (GermId, Germ) -> GameM Bool
      f' (_, g) = f g
  filterM f' germPs

----------------------------------------------------------------------------------------------------
--
-- Physics is reponsible for updating the [gsRender] field of the GameState.
--
physics :: Time -> GameM ()
physics duration = do
  gs <- get
  -- grow the germs. This updates their position in Hipmunk
  mapM_ (growGerm duration) (M.keys $ gsGerms gs)
  -- selected germs stay where they are.
  let getPos (_, g) = do
        let hc = germHipCirc g
        pos <- runOnHipState $ getHipCircPos hc
        return (hc, pos)
  selected <- germsSatisfying germSelected
  poses <- mapM getPos selected
  ----
  runOnHipState $ hipStep duration -- replicateM 10 (hipStep (duration/10))
  ----
  -- reset position of those germs
  let setPos (hc, pos) = runOnHipState $ setHipCircPosVel hc pos (R2 0 0)
  mapM_ setPos poses
  ----
  clearRender
  gameFieldRender
  sideBarRender

----------------------------------------------------------------------------------------------------
addRender :: GLM () -> GameM ()
addRender glm = modify $ \gs -> gs { gsRender = gsRender gs >> glm }

----------------------------------------------------------------------------------------------------

clearRender :: GameM ()
clearRender = modify $ \gs -> gs { gsRender = return () }

----------------------------------------------------------------------------------------------------
--
-- Update [gsRender] field of [GameState]
--
gameFieldRender :: GameM ()
gameFieldRender = do
  gs <- get
  let drawOneGerm :: (Int, Germ) -> GameM (GLM ())
      drawOneGerm (i,g) = do
        pos <- germPos g
        let (ampScale, timeScale) = scales g
        return $ (germGLFun . germGL $ g) i pos (germAnimTime g * timeScale)
                 (germSizeFun g (germCumulativeTime g)) ampScale
  renderGerms <-  sequence_ <$>  mapM drawOneGerm (zip [50..] $ M.elems $ gsGerms gs)
  --
  addRender renderGerms
  where
    -- germ gets angrier when selected
    scales g = if germSelected g then (1.2, 2.0) else (1.0, 1.0)

----------------------------------------------------------------------------------------------------
sideBarRender :: GameM ()
sideBarRender = do
  gs <- get
  let drawOneAntibiotic :: (Antibiotic, AntibioticData) -> GLM ()
      drawOneAntibiotic (ab, abd) =
        when (abEnabled abd) $ drawAntibiotic (abPos abd) ab (abEffectiveness abd)
      renderAntibiotics = mapM_ drawOneAntibiotic (M.toList $ gsAntibiotics gs)
  --
  let renderScore = do
        let x = sideBarLeft + sideBarWidth/3
            y = sideBarTop  - worldHeight/10
            x' = sideBarLeft + sideBarWidth*5/6
        h <- drawTextOfWidth scoreGrad (R2 x y) (sideBarWidth*2/3*0.8) "Score:"
        drawTextOfHeight_ scoreGrad (R2 x' y) h $ printf "%4d" $ gsScore gs
  --
  addRender (renderAntibiotics >> renderScore)

----------------------------------------------------------------------------------------------------
playingLevelSelect :: R2 -> GameM FSMState
playingLevelSelect p = do
  germsToSelect <- germsSatisfyingM (pointCollides p)
  let select g = g { germSelected = True }
  mapM_ (updateGerm select) germsToSelect
  return FSMPlayingLevel

----------------------------------------------------------------------------------------------------
playingLevelUnselect :: R2 -> GameM FSMState
playingLevelUnselect p = do
  let collideSelected g = do { b <- pointCollides p g; return $ germSelected g && b }
  germsToUnselect <- germsSatisfyingM collideSelected
  let unselect g = g { germSelected = False }
  mapM_ (updateGerm unselect) germsToUnselect
  return FSMPlayingLevel

----------------------------------------------------------------------------------------------------
-- FIXME: Move somewhere else
unselect :: Germ -> Germ
unselect g = g { germSelected = False }
----------------------------------------------------------------------------------------------------
playingLevelDrag :: R2 -> R2 -> GameM FSMState
playingLevelDrag p p' = do
  germsToDrag <- germsSatisfyingM (pointCollides p)
  case germsToDrag of
    []         -> return ()
    gp@(_,g):_ -> do
      inField <- isInGameField g
      if inField then runOnHipState $ setHipCircPosVel (germHipCirc g) p' (R2 0 0)
                 else updateGerm unselect gp
  return FSMPlayingLevel
  where
    isInGameField :: Germ -> GameM Bool
    isInGameField g = do
      gs <- get
      R2 x y <- runHipM (gsHipState gs) $ getHipCircPos $ germHipCirc g
      return $ x >= fieldLeft && x <= fieldRight && y >= fieldBottom && y <= fieldTop
----------------------------------------------------------------------------------------------------
-- FIXME: Use a bloody lens!
enableAntibiotic :: Antibiotic -> GameM ()
enableAntibiotic ab = do
  let enable abd = abd { abEnabled = True }
  modifyAntibiotic enable ab


-- FIXME: use a bloody lens!
modifyAntibioticEffectiveness :: (Double -> Double) -> Antibiotic -> GameM ()
modifyAntibioticEffectiveness f ab = do
  let mod abd = abd  { abEffectiveness = f (abEffectiveness abd) }

  modifyAntibiotic mod ab

modifyAntibiotic :: (AntibioticData -> AntibioticData) -> Antibiotic -> GameM ()
modifyAntibiotic f ab = do
  gs <- get
  let m = gsAntibiotics gs
  case M.lookup ab m of
    Just abd -> do
      printStrLn "Antibiotic modified\n"
      let m' = M.insert ab (f abd) m
      put $ gs { gsAntibiotics = m' }
    Nothing -> return ()
----------------------------------------------------------------------------------------------------
whenEventsMutedOtherwise :: UTCTime -> GameM a -> GameM a -> GameM a
whenEventsMutedOtherwise t dflt gm = do
  d <- timeSince t
  if (d >= eventMuteTime) then gm else dflt

----------------------------------------------------------------------------------------------------
