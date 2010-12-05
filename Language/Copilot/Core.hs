{-# LANGUAGE GADTs, RankNTypes, ScopedTypeVariables, FlexibleContexts, 
    FlexibleInstances #-}

-- | Provides basic types and functions for other parts of /Copilot/.
--
-- If you wish to add a new type, you need to make it an instance of @'Streamable'@,
-- to add it to @'foldStreamableMaps'@, @'mapStreamableMaps'@, and optionnaly 
-- to add an ext[Type], a [type] and a var[Type]
-- functions in Language.hs to make it easier to use. 
module Language.Copilot.Core (
        -- * Type hierarchy for the copilot language
        Var, Name, Period, Phase, Port(..), Ext(..),
        Exs, ExtRet(..), Args,
        Spec(..), Streams, Stream, Send(..), --DistributedStreams,
        Trigger(..), Triggers, notVarErr, LangElems(..),
	-- * General functions on 'Streams' and 'StreamableMaps'
	Streamable(..), mkSend, -- Sendable(..)
        StreamableMaps(..), emptySM,
        isEmptySM, getMaybeElem, getElem, 
        foldStreamableMaps, --foldSendableMaps, 
        mapStreamableMaps, mapStreamableMapsM,
        filterStreamableMaps, normalizeVar, getVars, Vars,
        -- compiler
        BoundedArray(..), nextSt, Outputs, TmpSamples(..), emptyTmpSamples, 
        ProphArrs, Indexes, PhasedValueVar(..), PhasedValueArr(..), PhasedValueIdx(..),
        tmpVarName, tmpArrName, getAtomType,
        getSpecs, getSends, getTriggers, makeTrigger -- XXX compiler
    ) where

import qualified Language.Atom as A

import Data.Int
import Data.Word
import Data.List hiding (union)
import qualified Data.Map as M
import Text.Printf
import Control.Monad.Writer (Writer, Monoid(..), execWriter)

---- Type hierarchy for the copilot language -----------------------------------

-- | Names of the streams or external variables
type Var = String
-- | C file name
type Name = String
-- | Atom period
type Period = Int
-- | Phase of an Atom phase
type Phase = Int
-- | Port over which to broadcast information
data Port = Port Int

-- | Specification of a stream, parameterized by the type of the values of the stream.
-- The only requirement on @a@ is that it should be 'Streamable'.
data Spec a where
    Var :: Streamable a => Var -> Spec a
    Const :: Streamable a => a -> Spec a

    PVar :: Streamable a => A.Type -> Ext -> Phase -> Spec a
    PArr :: (Streamable a, Streamable b, A.IntegralE b) 
         => A.Type -> (Ext, Spec b) -> Phase -> Spec a

    F :: (Streamable a, Streamable b) => 
	    (b -> a) -> (A.E b -> A.E a) -> Spec b -> Spec a
    F2 :: (Streamable a, Streamable b, Streamable c) => 
        (b -> c -> a) -> (A.E b -> A.E c -> A.E a) -> Spec b -> Spec c -> Spec a
    F3 :: (Streamable a, Streamable b, Streamable c, Streamable d) => 
        (b -> c -> d -> a) -> (A.E b -> A.E c -> A.E d -> A.E a) 
                           -> Spec b -> Spec c -> Spec d -> Spec a

    Append :: Streamable a => [a] -> Spec a -> Spec a
    Drop :: Streamable a => Int -> Spec a -> Spec a

-- | Arguments to be passed to a C function.
type Args = ([Var], StreamableMaps Spec)

-- XXX change the constructors to SimpleVar and Function (or something like that)
-- | Holds external variables or external functions to call.
data Ext = ExtV Var
         | Fun String Args

-- XXX are these necessary (redundant)?  Used in Analysis and AtomToC
type Exs = (A.Type, Ext, ExtRet)

data ExtRet = ExtRetV Phase 
            | ExtRetA Phase String
  deriving Eq

instance Show Ext where
  show (ExtV v) = v
  show (Fun f (args, _)) = f ++ "(" ++ unwords args ++ ")"

instance Eq Ext where
  (==) (ExtV v0) (ExtV v1) = v0 == v1
  (==) (Fun f0 (l0, _)) (Fun f1 (l1, _)) = f0 == f1 && l0 == l1  
  (==) _ _ = False

-- These belong in Language.hs, but we don't want orphan instances.
instance (Streamable a, A.NumE a) => Num (Spec a) where
    (+) = F2 (+) (+) -- A.NumE a => E a is an instance of Num
    (*) = F2 (*) (*)
    (-) = F2 (-) (-)
    negate = F negate negate
    abs = F abs abs
    signum = F signum signum
    fromInteger i = Const (fromInteger i)

instance (Streamable a, A.NumE a, Fractional a) => Fractional (Spec a) where
    (/) = F2 (/) (/)
    recip = F recip recip
    fromRational r = Const (fromRational r)

{-# RULES
"Copilot.Core appendAppend" forall ls1 ls2 s. Append ls1 (Append ls2 s) = Append (ls1 ++ ls2) s
"Copilot.Core dropDrop" forall i1 i2 s. Drop i1 (Drop i2 s) = Drop (i1 + i2) s
"Copilot.Core dropConst" forall i x. Drop i (Const x) = Const x
"Copilot.Core FConst" forall fI fC x0. F fI fC (Const x0) = Const (fI x0)
"Copilot.Core F2Const" forall fI fC x0 x1. F2 fI fC (Const x0) (Const x1) = Const (fI x0 x1)
"Copilot.Core F3Const" forall fI fC x0 x1 x2. F3 fI fC (Const x0) (Const x1) (Const x2) = Const (fI x0 x1 x2)
    #-}

instance Eq a => Eq (Spec a) where
    (==) (PVar t v ph) (PVar t' v' ph') = t == t' && v == v' && ph == ph'
    (==) (PArr t (v, idx) ph) (PArr t' (v', idx') ph') = 
           t == t' && v == v' && show idx == show idx' && ph == ph'
    (==) (Var v) (Var v') = v == v'
    (==) (Const x) (Const x') = x == x'
    (==) s@(F _ _ _) s'@(F _ _ _) = show s == show s'
    (==) s@(F2 _ _ _ _) s'@(F2 _ _ _ _) = show s == show s'
    (==) s@(F3 _ _ _ _ _) s'@(F3 _ _ _ _ _) = show s == show s'
    (==) (Append ls s) (Append ls' s') = ls == ls' && s == s'
    (==) (Drop i s) (Drop i' s') = i == i' && s == s'
    (==) _ _ = False

-- | An instruction to send data on a port at a given phase.  Uses a phantom type.
-- data Send a = Sendable a => Send (Var, Phase, Port)
data Send a =  
  Send { sendVar  :: Spec a 
       , sendPh   :: Phase
       , sendPort :: Port
       , sendName :: String}

instance Streamable a => Show (Send a) where 
  show (Send s ph (Port port) portName) = 
    notVarErr s (\var -> (portName ++ "_port_" ++ show port ++ "_var_" 
                            ++ var ++ "_ph_" ++ show ph))
data Trigger =
  Trigger { trigVar  :: Spec Bool
          , trigName :: String
          -- We carry around both the value and the vars of the arguments to be
          -- passed to the trigger.  The vars are used to put the arguments in
          -- the correct order, since the values are stored in a map, destroying
          -- their order.
          , trigArgs :: ([Var], StreamableMaps Spec)} 

type Triggers = M.Map String Trigger

instance Show Trigger where 
  show (Trigger s fnName _) =
    notVarErr s (\var -> ("trigger_" ++ var ++ "_" ++ fnName ++ "_")) -- XXX add args
--                            ++ map (\x -> if x == ' ' then '_' else x) 
--                                   (concatMap show args)))

-- | Holds all the different kinds of language elements that are pushed into the
-- Writer monad.  This currently includes the actual specs, "send" directives,
-- and trigger directives. (Use the functions in Language.hs to make sends and
-- triggers.)
data LangElems = LangElems 
       { strms :: StreamableMaps Spec
       , snds  :: StreamableMaps Send
       , trigs :: Triggers}

-- | Container for mutually recursive streams, whose specifications may be
-- parameterized by different types
type Streams = Writer LangElems ()

getSpecs :: Streams -> StreamableMaps Spec
getSpecs streams = 
  let (LangElems ss _ _) = execWriter streams
  in  ss

getSends :: Streams -> StreamableMaps Send
getSends streams = 
  let (LangElems _ snds _) = execWriter streams
  in  snds

getTriggers :: Streams -> Triggers
getTriggers streams = 
  let (LangElems _ _ triggers) = execWriter streams
  in  triggers

-- | A named stream
type Stream a = Streamable a => (Var, Spec a)


-- | Holds the complete specification of a distributed monitor
-- type DistributedStreams = (Streams, Sends)

---- General functions on streams ----------------------------------------------

-- | A type is streamable iff a stream may emit values of that type
-- 
-- There are very strong links between @'Streamable'@ and @'StreamableMaps'@ :
-- the types aggregated in @'StreamableMaps'@ are exactly the @'Streamable'@
-- types and that invariant should be kept (see methods)
class (A.Expr a, A.Assign a, Show a) => Streamable a where
    -- | Provides access to the Map in a StreamableMaps which store values
    -- of the good type
    getSubMap :: StreamableMaps b -> M.Map Var (b a)

    -- | Provides a way to modify (mostly used for insertions) the Map in a
    -- StreamableMaps which store values of the good type
    updateSubMap :: (M.Map Var (b a) -> M.Map Var (b a)) 
                 -> StreamableMaps b -> StreamableMaps b

    -- | A default value for the type @a@. Its value is not important.
    unit :: a
    
    -- | A constructor to produce an @Atom@ value
    atomConstructor :: Var -> a -> A.Atom (A.V a)

    -- | A constructor to get an @Atom@ value from an external variable
    externalAtomConstructor :: Var -> A.V a

    -- | The argument only coerces the type, it is discarded.  Returns the
    -- format for outputting a value of this type with printf in C
    --
    -- For example "%f" for a float
    typeId :: a -> String
    
    -- | The same, only adds the wanted precision for floating points.
    typeIdPrec :: a -> String
    typeIdPrec x = typeId x
    
    -- | The argument only coerces the type, it is discarded.
    -- Returns the corresponding /Atom/ type.
    atomType :: a -> A.Type
    
    -- | Like Show, except that the formatting is exactly the same as the one of
    -- C for example the booleans are first converted to 0 or 1, and floats and
    -- doubles have the good precision.
    showAsC :: a -> String
 
-- | If the 'Spec' isn't a 'Var', then throw an error; otherwise, apply the
-- function.
notVarErr :: Streamable a => Spec a -> (Var -> b) -> b
notVarErr s f =
  case s of
    Var v -> f v
    _     -> error $ "You provided specification \n" ++ show s 
                      ++ "\n where you needed to give a variable."

-- | Sending data over ports.
mkSend :: (Streamable a) => A.E a -> Port -> String -> A.Atom ()
mkSend e (Port port) portName =
  A.action (\[ueStr] -> portName ++ "(" ++ ueStr ++ "," ++ show port ++ ")") 
           [A.ue e]

instance Streamable Bool where
    getSubMap = bMap
    updateSubMap f sm = sm {bMap = f $ bMap sm}
    unit = False
    atomConstructor = A.bool
    externalAtomConstructor = A.bool'
    typeId _ = "%i"
    atomType _ = A.Bool
    showAsC x = printf "%u" (if x then 1::Int else 0)
instance Streamable Int8 where
    getSubMap = i8Map
    updateSubMap f sm = sm {i8Map = f $ i8Map sm}
    unit = 0
    atomConstructor = A.int8
    externalAtomConstructor = A.int8'
    typeId _ = "%d"
    atomType _ = A.Int8
    showAsC x = printf "%d" (toInteger x)
instance Streamable Int16 where
    getSubMap = i16Map
    updateSubMap f sm = sm {i16Map = f $ i16Map sm}
    unit = 0
    atomConstructor = A.int16
    externalAtomConstructor = A.int16'
    typeId _ = "%d"
    atomType _ = A.Int16
    showAsC x = printf "%d" (toInteger x)
instance Streamable Int32 where
    getSubMap = i32Map
    updateSubMap f sm = sm {i32Map = f $ i32Map sm}
    unit = 0
    atomConstructor = A.int32
    externalAtomConstructor = A.int32'
    typeId _ = "%d"
    atomType _ = A.Int32
    showAsC x = printf "%d" (toInteger x)
instance Streamable Int64 where
    getSubMap = i64Map
    updateSubMap f sm = sm {i64Map = f $ i64Map sm}
    unit = 0
    atomConstructor = A.int64
    externalAtomConstructor = A.int64'
    typeId _ = "%lld"
    atomType _ = A.Int64
    showAsC x = printf "%d" (toInteger x)
instance Streamable Word8 where
    getSubMap = w8Map
    updateSubMap f sm = sm {w8Map = f $ w8Map sm}
    unit = 0
    atomConstructor = A.word8
    externalAtomConstructor = A.word8'
    typeId _ = "%u"
    atomType _ = A.Word8
    showAsC x = printf "%u" (toInteger x)
instance Streamable Word16 where
    getSubMap = w16Map
    updateSubMap f sm = sm {w16Map = f $ w16Map sm}
    unit = 0
    atomConstructor = A.word16
    externalAtomConstructor = A.word16'
    typeId _ = "%u"
    atomType _ = A.Word16
    showAsC x = printf "%u" (toInteger x)
instance Streamable Word32 where
    getSubMap = w32Map
    updateSubMap f sm = sm {w32Map = f $ w32Map sm}
    unit = 0
    atomConstructor = A.word32
    externalAtomConstructor = A.word32'
    typeId _ = "%u"
    atomType _ = A.Word32
    showAsC x = printf "%u" (toInteger x)
instance Streamable Word64 where
    getSubMap = w64Map
    updateSubMap f sm = sm {w64Map = f $ w64Map sm}
    unit = 0
    atomConstructor = A.word64
    externalAtomConstructor = A.word64'
    typeId _ = "%llu"
    atomType _ = A.Word64
    showAsC x = printf "%u" (toInteger x)
instance Streamable Float where
    getSubMap = fMap
    updateSubMap f sm = sm {fMap = f $ fMap sm}
    unit = 0
    atomConstructor = A.float
    externalAtomConstructor = A.float'
    typeId _ = "%f"
    typeIdPrec _ = "%.5f"
    atomType _ = A.Float
    showAsC x = printf "%.5f" x
instance Streamable Double where
    getSubMap = dMap
    updateSubMap f sm = sm {dMap = f $ dMap sm}
    unit = 0
    atomConstructor = A.double
    externalAtomConstructor = A.double'
    typeId _ = "%lf"
    typeIdPrec _ = "%.10lf"
    atomType _ = A.Double
    showAsC x = printf "%.10f" x

-- | Lookup into the map of the right type in @'StreamableMaps'@
{-# INLINE getMaybeElem #-}
getMaybeElem :: Streamable a => Var -> StreamableMaps b -> Maybe (b a)
getMaybeElem v sm = M.lookup v $ getSubMap sm

-- | Lookup into the map of the right type in @'StreamableMaps'@
-- Launch an exception if the index is not in it
{-# INLINE getElem #-}
getElem :: Streamable a => Var -> StreamableMaps b -> b a
getElem v sm = case getMaybeElem v sm of
                 Nothing -> error "Error in application of getElem from Core.hs."
                 Just x -> x

getAtomType :: Streamable a => Spec a -> A.Type
getAtomType s =
  let unitElem = unit
      _ = (Const unitElem) `asTypeOf` s -- to help the typechecker
  in atomType unitElem

-- | This function is used to iterate on all the values in all the maps stored
-- by a @'StreamableMaps'@, accumulating a value over time
{-# INLINE foldStreamableMaps #-}
foldStreamableMaps :: forall b c. 
    (Streamable a => Var -> c a -> b -> b) -> 
    StreamableMaps c -> b -> b
foldStreamableMaps f (SM bm i8m i16m i32m i64m w8m w16m w32m w64m fm dm) acc =
    let acc0  = M.foldWithKey f acc  bm
        acc1  = M.foldWithKey f acc0 i8m        
        acc2  = M.foldWithKey f acc1 i16m
        acc3  = M.foldWithKey f acc2 i32m
        acc4  = M.foldWithKey f acc3 i64m
        acc5  = M.foldWithKey f acc4 w8m
        acc6  = M.foldWithKey f acc5 w16m
        acc7  = M.foldWithKey f acc6 w32m
        acc8  = M.foldWithKey f acc7 w64m
        acc9  = M.foldWithKey f acc8 fm      
        acc10 = M.foldWithKey f acc9 dm
    in acc10

{-# INLINE mapStreamableMaps #-}
mapStreamableMaps :: forall s s'. 
    (forall a. Streamable a => Var -> s a -> s' a) -> 
    StreamableMaps s -> StreamableMaps s'
mapStreamableMaps f (SM bm i8m i16m i32m i64m w8m w16m w32m w64m fm dm) =
    SM {
            bMap = M.mapWithKey f bm,
            i8Map = M.mapWithKey f i8m,
            i16Map = M.mapWithKey f i16m,
            i32Map = M.mapWithKey f i32m,
            i64Map = M.mapWithKey f i64m,
            w8Map = M.mapWithKey f w8m,
            w16Map = M.mapWithKey f w16m,
            w32Map = M.mapWithKey f w32m,
            w64Map = M.mapWithKey f w64m,
            fMap = M.mapWithKey f fm,
            dMap = M.mapWithKey f dm
        }

{-# INLINE mapStreamableMapsM #-}
mapStreamableMapsM :: forall s s' m. Monad m => 
    (Streamable a => Var -> s a -> m (s' a)) -> 
    StreamableMaps s -> m (StreamableMaps s')
mapStreamableMapsM f sm =
    foldStreamableMaps (
            \ v s sm'M ->  do
                    sm' <- sm'M
                    s' <- f v s
                    return $ updateSubMap (\ m -> M.insert v s' m) sm'
        ) sm (return emptySM)

-- | Only keeps in @sm@ the values whose key+type are in @l@.  Also returns a
-- bool saying whether all the elements in sm were in l.  Works even if some
-- elements in @l@ are not in @sm@.  Not optimised at all.
filterStreamableMaps :: 
  forall c b. StreamableMaps c -> [(A.Type, Var, b)] -> (StreamableMaps c, Bool)
filterStreamableMaps sm l =
    let (sm2, l2) = foldStreamableMaps filterElem sm (emptySM, []) in
    (sm2, (l' \\ nub l2) == [])
    where
        filterElem :: forall a. Streamable a => Var -> c a -> 
            (StreamableMaps c, [(A.Type, Var)]) -> 
            (StreamableMaps c, [(A.Type, Var)])
        filterElem v s (sm', l2) =
            let x = (atomType (unit::a), v) in
            if x `elem` l'
                then (updateSubMap (\m -> M.insert v s m) sm', x:l2)
                else (sm', l2)
        l' = nub $ map (\(x,y,_) -> (x,y)) l

-- | This is a generalization of @'Streams'@
-- which is used for storing Maps over values parameterized by different types.
--
-- It is extensively used in the internals of Copilot, in conjunction with
-- @'foldStreamableMaps'@ and @'mapStreamableMaps'@
data StreamableMaps a =
    SM {
            bMap   :: M.Map Var (a Bool),
            i8Map  :: M.Map Var (a Int8),
            i16Map :: M.Map Var (a Int16),
            i32Map :: M.Map Var (a Int32),
            i64Map :: M.Map Var (a Int64),
            w8Map  :: M.Map Var (a Word8),
            w16Map :: M.Map Var (a Word16),
            w32Map :: M.Map Var (a Word32),
            w64Map :: M.Map Var (a Word64),
            fMap   :: M.Map Var (a Float),
            dMap   :: M.Map Var (a Double)
        }

instance Monoid (StreamableMaps Spec) where
  mempty = emptySM
  mappend x y = overlap x y

instance Monoid LangElems where
  mempty = LangElems emptySM emptySM M.empty
  mappend (LangElems x y z) (LangElems x' y' z') = 
    LangElems (overlap x x') (overlap y y') (M.union z z') -- XXX should we test for the same key? 
overlap :: StreamableMaps s -> StreamableMaps s -> StreamableMaps s 
overlap x@(SM bm i8m i16m i32m i64m w8m w16m w32m w64m fm dm) 
        y@(SM bm' i8m' i16m' i32m' i64m' w8m' w16m' w32m' w64m' fm' dm') =
  let multDefs = (getVars x `intersect` getVars y)
  in  if null multDefs then union
        else error $ "Copilot error: The variables " 
                                   ++ show multDefs ++ " have multiple definitions."
  where union = SM (M.union bm bm') (M.union i8m i8m') (M.union i16m i16m') 
                   (M.union i32m i32m') (M.union i64m i64m') (M.union w8m w8m') 
                   (M.union w16m w16m') (M.union w32m w32m') (M.union w64m w64m') 
                   (M.union fm fm') (M.union dm dm')

-- | Get the Copilot variables.
getVars :: StreamableMaps s -> [Var]
getVars streams = foldStreamableMaps (\k _ ks -> k:ks) streams []                         

-- | An empty streamableMaps. 
emptySM :: StreamableMaps a
emptySM = SM
    {
        bMap = M.empty, 
        i8Map = M.empty,
        i16Map = M.empty,
        i32Map = M.empty,
        i64Map = M.empty,
        w8Map = M.empty,
        w16Map = M.empty,
        w32Map = M.empty,
        w64Map = M.empty,
        fMap = M.empty,
        dMap = M.empty 
    }

-- | Verifies if its argument is equal to emptySM
isEmptySM :: StreamableMaps a -> Bool
isEmptySM (SM bm i8m i16m i32m i64m w8m w16m w32m w64m fm dm) = 
    M.null bm &&
        M.null i8m &&
        M.null i16m &&
        M.null i32m &&
        M.null i64m &&
        M.null w8m &&
        M.null w16m &&
        M.null w32m &&
        M.null w64m &&
        M.null fm &&
        M.null dm 

-- | Replace all accepted special characters by sequences of underscores.  
normalizeVar :: Var -> Var
normalizeVar v =
    foldl (\ acc c -> acc ++ case c of 
                               '.' -> "_" 
                               '[' -> "_"  
                               ']' -> "_"  
                               ' ' -> "_"
                               _ -> [c]) 
          "" v

-- | For each typed variable, this type holds all its successive values in an infinite list
-- Beware : each element of one of those lists corresponds to a full @Atom@ period, 
-- not to a single clock tick.
type Vars = StreamableMaps []

-- Pretty printer: can't put in PrettyPrinter since that causes circular deps.

instance Show a => Show (Spec a) where
    show s = showIndented s 0

showIndented :: Spec a -> Int -> String
showIndented s n =
    let tabs = concat $ replicate n "  " in
    tabs ++ showRaw s n

showRaw :: Spec a -> Int -> String
showRaw (PVar t v ph) _ = "PVar " ++ show t ++ " " ++ show v ++ " " ++ show ph
showRaw (PArr t (v, idx) ph) _ = 
  "PArr " ++ show t ++ " (" ++ show v ++ " ! (" ++ show idx ++ ")) " ++ show ph
showRaw (Var v) _ = "Var " ++ v
showRaw (Const e) _ = "Const " ++ show e
showRaw (F _ _ s0) n = 
    "F op? (\n" ++ 
        showIndented s0 (n + 1) ++ "\n" ++ 
        (concat $ replicate n "  ") ++ ")"
showRaw (F2 _ _ s0 s1) n = 
    "F2 op? (\n" ++
        showIndented s0 (n + 1) ++ "\n" ++ 
        showIndented s1 (n + 1) ++ "\n" ++ 
        (concat $ replicate n "  ") ++ ")"
showRaw (F3 _ _ s0 s1 s2) n = 
    "F3 op? (\n" ++ 
        showIndented s0 (n + 1) ++ "\n" ++ 
        showIndented s1 (n + 1) ++ "\n" ++ 
        showIndented s2 (n + 1) ++ "\n" ++ 
        (concat $ replicate n "  ") ++ ")"
showRaw (Append ls s0) n = 
    "Append " ++ show ls ++ " (\n" ++
        showIndented s0 (n + 1) ++ "\n" ++ 
        (concat $ replicate n "  ") ++ ")"
showRaw (Drop i s0) n = 
    "Drop " ++ show i ++ " (\n" ++
        showIndented s0 (n + 1) ++ "\n" ++ 
        (concat $ replicate n "  ") ++ ")"



-- XXX
-- Compiler: the code below really belongs in Compiler.hs, but its called by
-- makeTrigger, which is a method of the class Streamable.

-- | To make customer C triggers.  Only for Spec Bool (others throw an
-- error).  
makeTrigger :: StreamableMaps Spec -> ProphArrs -> TmpSamples -> Indexes 
            -> Trigger -> A.Atom () -> A.Atom ()
makeTrigger streams prophArrs tmpSamples outputIndexes 
            trigger@(Trigger s fnName (vars,args)) r = 
  do r 
     A.liftIO $ putStrLn ("len" ++ (show $ length vars)) 
     (A.exactPhase 0 $ A.atom (show trigger) $ 
        do A.cond (nextSt streams prophArrs tmpSamples outputIndexes s 0)
           A.action (\ues -> fnName ++ "(" ++ unwords (intersperse "," ues) ++ ")")
              (reorder vars []
                (foldStreamableMaps 
                  (\v argSpec ls -> (v,next argSpec):ls) args [])))
     where next :: Streamable a => Spec a -> A.UE 
           next a = A.ue $ nextSt streams prophArrs 
                             tmpSamples outputIndexes a 0
           reorder [] acc _ = reverse $ snd (unzip acc)
           reorder (v:vs) acc ls = 
               case lookup v ls of
                 Nothing -> error "Error in makeTrigger in Core.hs."
                 Just x  -> let n = (v,x)
                            in reorder vs (n:acc) ls

-- For the prophecy arrays
type ArrIndex = Word64
type ProphArrs = StreamableMaps BoundedArray
type Outputs = StreamableMaps A.V
type Indexes = M.Map Var (A.V ArrIndex)

-- External variables
data PhasedValueVar a = PhV Phase (A.V a)
--type TmpVarSamples = StreamableMaps PhasedValueVar

tmpVarName :: Ext -> Phase -> Var
tmpVarName v ph = show v ++ "_" ++ show ph

-- External arrays
data PhasedValueArr a = PhA Phase (A.V a) -- Array name.
data PhasedValueIdx a = PhIdx (A.E a) -- variable that gives index. 

data TmpSamples = 
  TmpSamples { tmpVars :: StreamableMaps PhasedValueVar
             , tmpArrs :: StreamableMaps PhasedValueArr
             , tmpIdxs :: StreamableMaps PhasedValueIdx
             }

emptyTmpSamples :: TmpSamples
emptyTmpSamples = TmpSamples emptySM emptySM emptySM

tmpArrName :: Ext -> Phase -> String -> Var
tmpArrName v ph idx = (tmpVarName v ph) ++ "_" ++ normalizeVar idx

data BoundedArray a = B ArrIndex (Maybe (A.A a))

nextSt :: Streamable a => StreamableMaps Spec -> ProphArrs -> TmpSamples -> Indexes 
       -> Spec a -> ArrIndex -> A.E a
nextSt streams prophArrs tmpSamples outputIndexes s index = 
    case s of
        PVar _ v ph  -> 
          let PhV _ var = getElem (tmpVarName v ph) (tmpVars tmpSamples) in
          A.value var
        PArr _ (v, idx) ph -> 
          let PhA _ var = e tmp (tmpArrs tmpSamples) 
              tmp = tmpArrName v ph (show idx) 
              e a b = case getMaybeElem a b of
                        Nothing -> 
                          error "Error in application of getElem in nextSt."
                        Just x  -> x 
          in A.value var
        Var v -> let B initLen maybeArr = getElem v prophArrs in
            -- This check is extremely important
            -- It means that if x at time n depends on y at time n
            -- then x is obtained not by y, but by inlining the definition of y
            -- so it increases the size of code (sadly),
            -- but is the only thing preventing race conditions from occuring
            if index < initLen
                then getVar v initLen maybeArr 
                else let s0 = getElem v streams in 
                     next s0 (index - initLen)
        Const e -> A.Const e
        F _ f s0 -> f $ next s0 index
        F2 _ f s0 s1 ->
            f (next s0 index) 
              (next s1 index)
        F3 _ f s0 s1 s2 ->
            f (next s0 index) 
              (next s1 index) 
              (next s2 index)
        Append _ s0 -> next s0 index
        Drop i s0 -> next s0 (fromInteger (toInteger i) + index)
    where
        next :: Streamable b => Spec b -> ArrIndex -> A.E b
        next = nextSt streams prophArrs tmpSamples outputIndexes 
        getVar :: Streamable a 
               => Var -> ArrIndex -> Maybe (A.A a) -> A.E a
        getVar v initLen maybeArr =
           let outputIndex = case M.lookup v outputIndexes of
                               Nothing -> error "Error in function getVar."
                               Just x -> x
               arr = case maybeArr of
                       Nothing -> error "Error in function getVar (maybeArr)."
                       Just x -> x in 
           arr A.!. ((A.Const index + A.VRef outputIndex) `A.mod_`  
                       (A.Const (initLen + 1)))
