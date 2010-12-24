module Language.Copilot.Examples.LTLExamples where

-- import Prelude (replicate, Int, replicate)
-- import qualified Prelude as P

import Language.Copilot
import Language.Copilot.Libs.Vote

import Prelude ()

maj0 :: Streams
maj0 = do
  let v = varW32 "v"
      b = varB "b"
      ls = [3, 2, 3, 0, 3, 3, 0]
  v .= majority ls
  b .= aMajority ls 3

maj1 :: Streams
maj1 = do
  let v0  = varW32 "v0"
      v1  = varW32 "v1"
      v2  = varW32 "v2"
      v3  = varW32 "v3"
      v4  = varW32 "v4"
      ans = varW32 "ans"
      chk = varB "chk"
      ls = [v0, v1, v2, v3, v4]
  v0  .= [3] ++ v0 + 1
  v1  .= [3] ++ v1 + 1
  v2  .= [1] ++ v2 + 1
  v3  .= [3] ++ v3 + 1
  v4  .= [1] ++ v4 + 1
  ans .= majority ls
  chk .= aMajority ls ans
