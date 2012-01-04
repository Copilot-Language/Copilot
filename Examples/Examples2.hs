module Examples2 ( examples2 ) where

import Prelude ()
import Language.Copilot

import qualified Copilot.Compile.SBV as S

import qualified Data.List as L

--------------------------------------------------------------------------------

{-
alt2 :: Stream Word64
alt2 = [0,1,2] ++ alt2 + 1

alt3 :: Stream Bool
alt3 = [True,True,False] ++ alt3

fib' :: Stream Word64
fib' = [0, 1] ++ fib' + drop 1 fib

fib :: Stream Word64
fib = [0, 1] ++ fib + drop 1 fib

fibSpec :: Spec
fibSpec = do
  trigger "fib_out" true [arg fib]
-}

nats :: Stream Word64
nats = [0] ++ nats + 1

alt :: Stream Bool
alt = [True] ++ not alt

logic :: Stream Bool
logic = [True, False] ++ logic || drop 1 logic

sumExterns :: Stream Word64
sumExterns =
  let
    e1 = extern "e1" (Just [0..])
    e2 = extern "e2" (Just $ L.cycle [2,3,4])
  in
    e1 + e2 + e1

spec :: Spec
spec = do
  trigger "trig1" alt [ arg $ nats < 3
                      , arg sumExterns 
                      , arg logic
                      ]

examples2 :: IO ()
examples2 = do
--  reify fibSpec >>= S.compile S.defaultParams
  reify spec >>= S.compile S.defaultParams 
