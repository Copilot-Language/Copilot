{-# LANGUAGE NoImplicitPrelude, Rank2Types, ScopedTypeVariables, FlexibleContexts #-}

-- | Describes the language /Copilot/.
--
-- If you wish to add a new operator, the only modification needed is adding it in this module.
-- But if you want it to be used in the random generated streams, add it to either @'opsF'@, @'opsF2'@ or @'opsF3'@
module Language.Copilot.Language (
        -- * Operators and functions
        mod, div, mod0, div0,
        (<), (<=), (==), (/=), (>=), (>),
        not, (||), (&&), (^), (==>),
        -- * Boolean constants
        Bool(..),
        -- * Arithmetic operators (derived)
        Num(..),
        -- * Division
        Fractional((/)),
        mux,
        CastIntTo(..),
        -- * The next functions are used only to coerce the type of their argument
        bool, int8, int16, int32, int64,
        word8, word16, word32, word64, float, double,
        -- * The next functions provide easier access to typed external variables.
        extB, extI8, extI16, extI32, extI64,
        extW8, extW16, extW32, extW64, extF, extD,
        -- * The next functions provide easier access to typed external arrays.
        extArrB, extArrI8, extArrI16, extArrI32, extArrI64,
        extArrW8, extArrW16, extArrW32, extArrW64, extArrF, extArrD,
        -- * Set of operators from which to choose during the generation of random streams
        opsF, opsF2, opsF3,
        -- * Constructs of the copilot language
        var, const, drop, (++), (.=), (..|), 
        -- * The next functions are typed variable declarations to help the type-checker.
        varB, varI8, varI16, varI32, varI64,
        varW8, varW16, varW32, varW64, varF, varD,
        -- * The next functions help typing the send operations
        -- Warning: there is no typechecking of that yet
        -- sendB, sendI8, sendI16, sendI32, sendI64,
        sendW8, -- , sendW16, sendW32, sendW64, sendF, sendD
        -- * Typed constant declarations.
        constB, constI8, constI16, constI32, constI64,
        constW8, constW16, constW32, constW64, constF, constD
    ) where

import qualified Language.Atom as A
import Data.Int
import Data.Word
import System.Random
import qualified Data.Map as M
import Prelude ( Bool(..), Num(..), Float, Double
               , Fractional(..), fromInteger, zip, Show(..), Integer)
import qualified Prelude as P
import Control.Monad.Writer

import Language.Copilot.Core
import Language.Copilot.Analyser
import Language.Copilot.Tests.Random

---- Operators and functions ---------------------------------------------------

not :: Spec Bool -> Spec Bool
not = F P.not A.not_


-- | Beware : crash without any possible recovery if a division by 0 happens.
-- Same risk with mod. Use div0 and mod0 if unsure.
mod, div :: (Streamable a, A.IntegralE a) => Spec a -> Spec a -> Spec a
mod = F2 P.mod A.mod_
div = F2 P.mod A.div_

-- | As mod and div, except that if the division would be by 0, the first
-- argument is used as a default.
mod0, div0 :: (Streamable a, A.IntegralE a) => a -> Spec a -> Spec a -> Spec a
mod0 d = F2 (\ x0 x1 -> if x1 P.== 0 then x0 `P.div` d 
                          else x0 `P.div` x1) (\ e0 e1 -> A.mod0_ e0 e1 d)
div0 d = F2 (\ x0 x1 -> if x1 P.== 0 then x0 `P.mod` d 
                          else x0 `P.mod` x1) (\ e0 e1 -> A.div0_ e0 e1 d)

(<), (<=), (>=), (>) :: (Streamable a, A.OrdE a) => Spec a -> Spec a -> Spec Bool
(<) = F2 (P.<) (A.<.)
(<=) = F2 (P.<=) (A.<=.)
(>=) = F2 (P.>=) (A.>=.)
(>) = F2 (P.>) (A.>.)

(==), (/=) :: (Streamable a, A.EqE a) => Spec a -> Spec a -> Spec Bool
(==) = F2 (P.==) (A.==.)
(/=) = F2 (P./=) (A./=.)

(||), (&&), (^), (==>) :: Spec Bool -> Spec Bool -> Spec Bool
(||) = F2 (P.||) (A.||.)
(&&) = F2 (P.&&) (A.&&.)
(^) = F2 
    (\ x y -> (x P.&& P.not y) P.|| (y P.&& P.not x)) 
    (\ x y -> (x A.&&. A.not_ y) A.||. (y A.&&. A.not_ x))
(==>) = F2 (\ x y -> y P.|| P.not x) A.imply

class (Streamable a, P.Integral a) => CastIntTo a where
    cast :: (Streamable b, A.IntegralE b) => Spec b -> Spec a

instance CastIntTo Word8 where
    cast = F (P.fromInteger P.. P.toInteger) (
            A.Retype P.. A.ue P.. (`A.mod_` (256::(A.E Word64))) P.. A.Retype P.. A.ue)
instance CastIntTo Word16 where
    cast = F (P.fromInteger P.. P.toInteger) (
            A.Retype P.. A.ue P.. (`A.mod_` (65536::(A.E Word64))) P.. A.Retype P.. A.ue)
instance CastIntTo Word32 where
    cast = F (P.fromInteger P.. P.toInteger) (
            A.Retype P.. A.ue P.. (`A.mod_` ((2 P.^ (32::Integer))::(A.E Word64))) P.. A.Retype P.. A.ue)
instance CastIntTo Word64 where
    cast = F (P.fromInteger P.. P.toInteger) (A.Retype P.. A.ue)

instance CastIntTo Int8 where
    cast = F (P.fromInteger P.. P.toInteger) (
            A.Retype P.. A.ue P.. (\x -> ((x P.+ (128::(A.E Word64))) 
                                          `A.mod_` 256) P.- 128) P.. A.Retype P.. A.ue)
instance CastIntTo Int16 where
    cast = F (P.fromInteger P.. P.toInteger) (
            A.Retype P.. A.ue P.. (\x -> ((x P.+ ((2 P.^ (15::Integer))::(A.E Word64))) 
                                          `A.mod_` (2 P.^ (16::Integer))) P.- (2 P.^ (15::Integer))) 
                                      P.. A.Retype P.. A.ue)
instance CastIntTo Int32 where
    cast = F (P.fromInteger P.. P.toInteger) (
            A.Retype P.. A.ue P.. (\x -> ((x P.+ (128::(A.E Word64))) 
                                          `A.mod_` 256) P.- 128) P.. A.Retype P.. A.ue)
instance CastIntTo Int64 where
    cast = F (P.fromInteger P.. P.toInteger) (
            A.Retype P.. A.ue P.. (\x -> ((x P.+ (128::(A.E Word64))) 
                                          `A.mod_` 256) P.- 128) P.. A.Retype P.. A.ue)


-- | Beware : both sides are executed, even if the result of one is later discarded
mux :: (Streamable a) => Spec Bool -> Spec a -> Spec a -> Spec a
mux = F3 (\ b x y -> if b then x else y) A.mux

infix 5 ==, /=, <, <=, >=, >
infixr 4 ||, &&, ^, ==>

-- Used for helping ghc in infering the type of the streams
bool :: Spec Bool -> Spec Bool
int8 :: Spec Int8 -> Spec Int8
int16 :: Spec Int16 -> Spec Int16
int32 :: Spec Int32 -> Spec Int32
int64 :: Spec Int64 -> Spec Int64
word8 :: Spec Word8 -> Spec Word8
word16 :: Spec Word16 -> Spec Word16
word32 :: Spec Word32 -> Spec Word32
word64 :: Spec Word64 -> Spec Word64
float :: Spec Float -> Spec Float
double :: Spec Double -> Spec Double
bool = P.id
int8 = P.id
int16 = P.id
int32 = P.id
int64 = P.id
word8 = P.id
word16 = P.id
word32 = P.id
word64 = P.id
float = P.id
double = P.id

-- Used for easily producing, and coercing PVars

-- for variables
extB :: Var -> Phase -> Spec Bool
extB = PVar A.Bool
extI8 :: Var -> Phase -> Spec Int8
extI8 = PVar A.Int8
extI16 :: Var -> Phase -> Spec Int16
extI16 = PVar A.Int16
extI32 :: Var -> Phase -> Spec Int32
extI32 = PVar A.Int32
extI64 :: Var -> Phase -> Spec Int64
extI64 = PVar A.Int64
extW8 :: Var -> Phase -> Spec Word8
extW8 = PVar A.Word8
extW16 :: Var -> Phase -> Spec Word16
extW16 = PVar A.Word16
extW32 :: Var -> Phase -> Spec Word32
extW32 = PVar A.Word32
extW64 :: Var -> Phase -> Spec Word64
extW64 = PVar A.Word64
extF :: Var -> Phase -> Spec Float
extF = PVar A.Float
extD :: Var -> Phase -> Spec Double
extD = PVar A.Double

-- for arrays 
-- inBounds :: (Integral a, Bounded a) => a -> Bool
-- inBounds a = 0 <= toIntger a <= toInteger maxBound

-- makeArrayCall :: (Streamable a, Integral a) => (Var, Spec a) -> Var
-- makeArrayCall (v, idx) = v P.++ "[" P.++ show idx P.++ "]"

  -- | let t = atomType idx 
  --   in t P.== A.Bool P.|| t P.== A.Float P.|| t P.== A.Double 
  --     = error $ "Copilot: " 
  -- | otherwise = v P.++ "[" P.++ show idx P.++ "]"

extArrB :: (Streamable a, A.IntegralE a) => (Var, Spec a) -> Phase -> Spec Bool
extArrB = \(v, idx) ph -> PArr A.Bool (v, idx) ph
extArrI8 :: (Streamable a, A.IntegralE a) => (Var, Spec a) -> Phase -> Spec Int8
extArrI8 = \(v, idx) ph -> PArr A.Int8 (v, idx) ph
extArrI16 :: (Streamable a, A.IntegralE a) => (Var, Spec a) -> Phase -> Spec Int16
extArrI16 = \(v, idx) ph -> PArr A.Int16 (v, idx) ph
extArrI32 :: (Streamable a, A.IntegralE a) => (Var, Spec a) -> Phase -> Spec Int32
extArrI32 = \(v, idx) ph -> PArr A.Int32 (v, idx) ph
extArrI64 :: (Streamable a, A.IntegralE a) => (Var, Spec a) -> Phase -> Spec Int64
extArrI64 = \(v, idx) ph -> PArr A.Int64 (v, idx) ph
extArrW8 :: (Streamable a, A.IntegralE a) => (Var, Spec a) -> Phase -> Spec Word8
extArrW8 = \(v, idx) ph -> PArr A.Word8 (v, idx) ph
extArrW16 :: (Streamable a, A.IntegralE a) => (Var, Spec a) -> Phase -> Spec Word16
extArrW16 = \(v, idx) ph -> PArr A.Word16 (v, idx) ph
extArrW32 :: (Streamable a, A.IntegralE a) => (Var, Spec a) -> Phase -> Spec Word32
extArrW32 = \(v, idx) ph -> PArr A.Word32 (v, idx) ph
extArrW64 :: (Streamable a, A.IntegralE a) => (Var, Spec a) -> Phase -> Spec Word64
extArrW64 = \(v, idx) ph -> PArr A.Word64 (v, idx) ph
extArrF :: (Streamable a, A.IntegralE a) => (Var, Spec a) -> Phase -> Spec Float
extArrF = \(v, idx) ph -> PArr A.Float (v, idx) ph
extArrD :: (Streamable a, A.IntegralE a) => (Var, Spec a) -> Phase -> Spec Double
extArrD = \(v, idx) ph -> PArr A.Double (v, idx) ph


---- Sets of operators for Tests.Random.hs -------------------------------------

---- Helper functions

mkOp :: (Random arg1, Streamable arg1) =>
    (Spec arg1 -> Spec r) -> Operator r
mkOp op =
    Operator (\ rand g ->
            let (s0, g0) = rand g FunSpecSet in
            (op s0, g0)
        )

mkOp2 :: (Random arg1, Random arg2, Streamable arg1, Streamable arg2) =>
    (Spec arg1 -> Spec arg2 -> Spec r) -> Operator r
mkOp2 op =
    Operator (\ rand g ->
            let (s0, g0) = rand g FunSpecSet 
                (s1, g1) = rand g0 FunSpecSet in
            (op s0 s1, g1)
        )
        
mkOp3 :: (Random arg1, Random arg2, Random arg3, 
    Streamable arg1, Streamable arg2, Streamable arg3) =>
    (Spec arg1 -> Spec arg2 -> Spec arg3 -> Spec r) -> Operator r
mkOp3 op =
    Operator (\ rand g ->
            let (s0, g0) = rand g FunSpecSet
                (s1, g1) = rand g0 FunSpecSet
                (s2, g2) = rand g1 FunSpecSet in
            (op s0 s1 s2, g2)
        )

mkOp2Coerce :: (Random arg1, Random arg2, Streamable arg1, Streamable arg2) =>
    (Spec arg1 -> Spec arg2 -> Spec r) -> arg1 -> arg2 -> Operator r
mkOp2Coerce op c0 c1 =
    Operator (\ rand g ->
            let (s0, g0) = rand g FunSpecSet
                (s1, g1) = rand g0 FunSpecSet in
            (op (s0 `P.asTypeOf` (Const c0)) (s1 `P.asTypeOf` (Const c1)), g1)
        )

mkOp2Ord :: forall r. (forall arg. 
    (Random arg, A.OrdE arg, Streamable arg) =>
    (Spec arg -> Spec arg -> Spec r)) 
    -> Operator r
mkOp2Ord op =
    let opI8, opI16, opI32, opI64, opW8, opW16, opW32, opW64, opF, opD :: 
            RandomGen g => 
            (forall a' g'. (Streamable a', Random a', RandomGen g') => g' -> SpecSet -> (Spec a', g')) -> g -> (Spec r, g)
        opI8 = fromOp P.$ mkOp2Coerce op (unit::Int8) (unit::Int8)
        opI16 = fromOp P.$ mkOp2Coerce op (unit::Int16) (unit::Int16)
        opI32 = fromOp P.$ mkOp2Coerce op (unit::Int32) (unit::Int32)
        opI64 = fromOp P.$ mkOp2Coerce op (unit::Int64) (unit::Int64)
        opW8 = fromOp P.$ mkOp2Coerce op (unit::Word8) (unit::Word8)
        opW16 = fromOp P.$ mkOp2Coerce op (unit::Word16) (unit::Word16)
        opW32 = fromOp P.$ mkOp2Coerce op (unit::Word32) (unit::Word32)
        opW64 = fromOp P.$ mkOp2Coerce op (unit::Word64) (unit::Word64)
        opF = fromOp P.$ mkOp2Coerce op (unit::Float) (unit::Float)
        opD = fromOp P.$ mkOp2Coerce op (unit::Double) (unit::Double) in
    Operator (\ rand g ->
            let (t, g0) = randomR (A.Int8, A.Double) g in
            case t of
                A.Int8 -> opI8 rand g0
                A.Int16 -> opI16 rand g0
                A.Int32 -> opI32 rand g0
                A.Int64 -> opI64 rand g0
                A.Word8 -> opW8 rand g0
                A.Word16 -> opW16 rand g0
                A.Word32 -> opW32 rand g0
                A.Word64 -> opW64 rand g0
                A.Float -> opF rand g0
                A.Double -> opD rand g0
                _ -> P.error "Impossible"
        )

mkOp2Eq :: forall r. (forall arg. 
    (Random arg, A.EqE arg, Streamable arg) =>
    (Spec arg -> Spec arg -> Spec r)) 
    -> Operator r
mkOp2Eq op =
    let opB, opI8, opI16, opI32, opI64, opW8, opW16, opW32, opW64, opF, opD :: 
            RandomGen g => 
            (forall a' g'. (Streamable a', Random a', RandomGen g') => g' -> SpecSet -> (Spec a', g')) -> g -> (Spec r, g)
        opB = fromOp P.$ mkOp2Coerce op (unit::Bool) (unit::Bool)
        opI8 = fromOp P.$ mkOp2Coerce op (unit::Int8) (unit::Int8)
        opI16 = fromOp P.$ mkOp2Coerce op (unit::Int16) (unit::Int16)
        opI32 = fromOp P.$ mkOp2Coerce op (unit::Int32) (unit::Int32)
        opI64 = fromOp P.$ mkOp2Coerce op (unit::Int64) (unit::Int64)
        opW8 = fromOp P.$ mkOp2Coerce op (unit::Word8) (unit::Word8)
        opW16 = fromOp P.$ mkOp2Coerce op (unit::Word16) (unit::Word16)
        opW32 = fromOp P.$ mkOp2Coerce op (unit::Word32) (unit::Word32)
        opW64 = fromOp P.$ mkOp2Coerce op (unit::Word64) (unit::Word64)
        opF = fromOp P.$ mkOp2Coerce op (unit::Float) (unit::Float)
        opD = fromOp P.$ mkOp2Coerce op (unit::Double) (unit::Double) in
    Operator (\ rand g ->
            let (t, g0) = random g in
            case t of
                A.Bool -> opB rand g0
                A.Int8 -> opI8 rand g0
                A.Int16 -> opI16 rand g0
                A.Int32 -> opI32 rand g0
                A.Int64 -> opI64 rand g0
                A.Word8 -> opW8 rand g0
                A.Word16 -> opW16 rand g0
                A.Word32 -> opW32 rand g0
                A.Word64 -> opW64 rand g0
                A.Float -> opF rand g0
                A.Double -> opD rand g0
        )

---- Definition of each operator

not_ :: Operator Bool
not_ = mkOp not    
    
(+$), (-$), (*$) :: (Streamable a, A.NumE a, Random a) => Operator a
(+$) = mkOp2 (P.+)
(-$) = mkOp2 (P.-)
(*$) = mkOp2 (P.*)

(/$) :: (Streamable a, A.NumE a, Fractional a, Random a) => Operator a
(/$) = mkOp2 (P./)

(<$), (<=$), (>=$), (>$) :: Operator Bool
(<$) = mkOp2Ord (<)
(<=$) = mkOp2Ord (<=)
(>=$) = mkOp2Ord (>=)
(>$) = mkOp2Ord (>)

(==$), (/=$) :: Operator Bool
(==$) = mkOp2Eq (==)
(/=$) = mkOp2Eq (/=)

(||$), (&&$), (^$), (==>$) :: Operator Bool
(||$) = mkOp2 (||)
(&&$) = mkOp2 (&&)
(^$) = mkOp2 (^)
(==>$) = mkOp2 (==>)

mux_ :: (Streamable a, Random a) => Operator a
mux_ = mkOp3 mux

-- Packing of the operators in StreamableMaps

createMapFromElems :: [val] -> M.Map Var val
createMapFromElems vals =
    let ks = [[x] | x <- ['a'..]]
        l = zip ks vals in
    M.fromAscList l

-- | opsF, opsF2 and opsF3 are feeded to Tests.Random.randomStreams.
-- They allows the random generated streams to include lots of operators.
-- If you add a new operator to Copilot, it would be nice to add it to one of those,
-- that way it could be used in the random streams used for testing.
-- opsF holds all the operators of arity 1, opsF2 of arity 2 and opsF3 of arity3
-- They are StreamableMaps, because operators are sorted based on their return type.
opsF, opsF2, opsF3 :: Operators
opsF = emptySM {bMap = createMapFromElems [not_]}

opsF2 = emptySM {
        bMap = createMapFromElems [(<$), (<=$), (>=$), (>$), (==$), (/=$), (||$), (&&$), (^$), (==>$)],
        i8Map = createMapFromElems [(+$), (-$), (*$)],
        i16Map = createMapFromElems [(+$), (-$), (*$)],
        i32Map = createMapFromElems [(+$), (-$), (*$)],
        i64Map = createMapFromElems [(+$), (-$), (*$)],
        w8Map = createMapFromElems [(+$), (-$), (*$)],
        w16Map = createMapFromElems [(+$), (-$), (*$)],
        w32Map = createMapFromElems [(+$), (-$), (*$)],
        w64Map = createMapFromElems [(+$), (-$), (*$)],
        fMap = createMapFromElems [(+$), (-$), (*$), (/$)],
        dMap = createMapFromElems [(+$), (-$), (*$), (/$)]
    }

opsF3 = emptySM {
        bMap = createMapFromElems [mux_],
        i8Map = createMapFromElems [mux_],
        i16Map = createMapFromElems [mux_],
        i32Map = createMapFromElems [mux_],
        i64Map = createMapFromElems [mux_],
        w8Map = createMapFromElems [mux_],
        w16Map = createMapFromElems [mux_],
        w32Map = createMapFromElems [mux_],
        w64Map = createMapFromElems [mux_],
        fMap = createMapFromElems [mux_],
        dMap = createMapFromElems [mux_]
    }

---- Constructs of the language ------------------------------------------------

-- | Stream variable reference
var :: Streamable a => Var -> Spec a
var v = Var v

-- If a generic 'var' declaration is insufficient for the type-checker to determine the type, a monomorphic var operator can be used
varB :: Var -> Spec Bool
varB = Var
varI8 :: Var -> Spec Int8
varI8 = Var
varI16 :: Var -> Spec Int16
varI16 = Var
varI32 :: Var -> Spec Int32
varI32 = Var
varI64 :: Var -> Spec Int64
varI64 = Var
varW8 :: Var -> Spec Word8
varW8 = Var 
varW16 :: Var -> Spec Word16
varW16 = Var
varW32 :: Var -> Spec Word32
varW32 = Var
varW64 :: Var -> Spec Word64
varW64 = Var
varF :: Var -> Spec Float
varF = Var
varD :: Var -> Spec Double
varD = Var

{-
sendB :: Var -> (Phase, Port) -> Send Bool
sendB v (ph, port) = Send (v, ph, port)
sendI8 :: Var -> (Phase, Port) -> Send Int8
sendI8 v (ph, port) = Send (v, ph, port)
sendI16 :: Var -> (Phase, Port) -> Send Int16
sendI16 v (ph, port) = Send (v, ph, port)
sendI32 :: Var -> (Phase, Port) -> Send Int32
sendI32 v (ph, port) = Send (v, ph, port)
sendI64 :: Var -> (Phase, Port) -> Send Int64
sendI64 v (ph, port) = Send (v, ph, port) -}
sendW8 :: Var -> (Phase, Port) -> Send Word8
sendW8 v (ph, port) = Send (v, ph, port)
{- sendW16 :: Var -> (Phase, Port) -> Send Word16
sendW16 v (ph, port) = Send (v, ph, port)
sendW32 :: Var -> (Phase, Port) -> Send Word32
sendW32 v (ph, port) = Send (v, ph, port)
sendW64 :: Var -> (Phase, Port) -> Send Word64
sendW64 v (ph, port) = Send (v, ph, port)
sendF :: Var -> (Phase, Port) -> Send Float
sendF v (ph, port) = Send (v, ph, port)
sendD :: Var -> (Phase, Port) -> Send Double
sendD v (ph, port) = Send (v, ph, port) -}

-- | A constant stream
const :: Streamable a => a -> Spec a
const x = Const x

constB :: Bool -> Spec Bool
constB = Const
constI8 :: Int8 -> Spec Int8
constI8 = Const
constI16 :: Int16 -> Spec Int16
constI16 = Const
constI32 :: Int32 -> Spec Int32
constI32 = Const
constI64 :: Int64 -> Spec Int64
constI64 = Const
constW8 :: Word8 -> Spec Word8
constW8 = Const 
constW16 :: Word16 -> Spec Word16
constW16 = Const
constW32 :: Word32 -> Spec Word32
constW32 = Const
constW64 :: Word64 -> Spec Word64
constW64 = Const
constF :: Float -> Spec Float
constF = Const
constD :: Double -> Spec Double
constD = Const


-- | Drop @i@ elements from a stream.
drop :: Streamable a => Int -> Spec a -> Spec a
drop i s = Drop i s

-- | Just a trivial wrapper over the @'Append'@ constructor
(++) :: Streamable a => [a] -> Spec a -> Spec a
ls ++ s = Append ls s

-- | Define a stream variable.
(.=) :: Streamable a => Var -> Spec a -> Streams
v .= s = tell (updateSubMap (M.insert v s) emptySM) 

-- | Allows to build a @'Sends'@ from specification
(..|) :: Sendable a => Send a -> Sends -> Sends
sendStmt@(Send (v, ph, port)) ..| sends = 
    updateSubMap (M.insert name sendStmt) sends
    where name = v P.++ "_" P.++ show ph P.++ "_" P.++ show port

infixr 3 ++
infixr 2 .=
infixr 1 ..|

---- Optimisation rules --------------------------------------------------------

{-# RULES
"Copilot.Language Plus0R" forall s. (P.+) s (Const 0) = s
"Copilot.Language Plus0L" forall s. (P.+) (Const 0) s = s
"Copilot.Language Minus0R" forall s. (P.-) s (Const 0) = s
"Copilot.Language Minus0L" forall s. (P.-) (Const 0) s = s
"Copilot.Language Times1R" forall s. (P.*) s (Const 1) = s
"Copilot.Language Times1L" forall s. (P.*) (Const 1) s = s
"Copilot.Language Times0R" forall s. (P.*) s (Const 0) = Const 0
"Copilot.Language Times0L" forall s. (P.*) (Const 0) s = Const 0
"Copilot.Language FracBy0" forall s. (P./) s (Const 0.0) = P.error "division by zero !" 
"Copilot.Language FracBy1" forall s. (P./) s (Const 1.0) = s 
"Copilot.Language Frac0" forall s. (P./) (Const 0.0) s = (Const 0.0)
"Copilot.Language OrFR" forall s. (||) s (Const False) = s
"Copilot.Language OrFL" forall s. (||) (Const False) s = s
"Copilot.Language OrTR" forall s. (||) s (Const True) = Const True
"Copilot.Language OrTL" forall s. (||) (Const True) s = Const True
"Copilot.Language AndFR" forall s. (&&) s (Const False) = Const False
"Copilot.Language AndFL" forall s. (&&) (Const False) s = Const False
"Copilot.Language AndTR" forall s. (&&) s (Const True) = s
"Copilot.Language AndTL" forall s. (&&) (Const True) s = s
"Copilot.Language ImpliesFL" forall s. (==>) (Const False) s = Const True
"Copilot.Language NotF" not (Const False) = Const True
"Copilot.Language NotT" not (Const True) = Const False
"Copilot.Language MuxF" forall s0 s1. mux (Const False) s0 s1 = s1
"Copilot.Language MuxT" forall s0 s1. mux (Const True) s0 s1 = s0
"Copilot.Language ImpliesDef" forall s0 s1. (||) s1 (not s0) = s0 ==> s1
    #-}
