--------------------------------------------------------------------------------
-- Copyright © 2011 National Institute of Aerospace / Galois, Inc.
--------------------------------------------------------------------------------

{-# LANGUAGE Rank2Types #-}

module Copilot.Compile.C99.C2A
  ( c2aExpr
  , c2aType
  ) where

import Copilot.Compile.C99.Witness
import Copilot.Compile.C99.MetaTable
import qualified Copilot.Core as C
import Copilot.Core.Type.Equality ((=~=), coerce, cong)
import qualified Data.Map as M
import Language.Atom ((!.), value, mod_)
import qualified Language.Atom as A
import Prelude hiding (id)

--------------------------------------------------------------------------------

c2aExpr :: MetaTable -> (forall η . C.Expr η => η α) -> A.E α
c2aExpr m e = c2aExpr_ e m

--------------------------------------------------------------------------------

c2aType :: C.Type α -> A.Type
c2aType t =
  case t of
    C.Bool   _ -> A.Bool
    C.Int8   _ -> A.Int8   ; C.Int16  _ -> A.Int16
    C.Int32  _ -> A.Int32  ; C.Int64  _ -> A.Int64
    C.Word8  _ -> A.Word8  ; C.Word16 _ -> A.Word16
    C.Word32 _ -> A.Word32 ; C.Word64 _ -> A.Word64
    C.Float  _ -> A.Float  ; C.Double _ -> A.Double

--------------------------------------------------------------------------------

newtype C2AExpr α = C2AExpr
  { c2aExpr_ :: MetaTable -> A.E α }

newtype C2AOp1 α β = C2AOp1
  { c2aOp1 :: A.E α -> A.E β }

newtype C2AOp2 α β γ = C2AOp2
  { c2aOp2 :: A.E α -> A.E β -> A.E γ }

newtype C2AOp3 α β γ δ = C2AOp3
  { c2aOp3 :: A.E α -> A.E β -> A.E γ -> A.E δ }

--------------------------------------------------------------------------------

instance C.Expr C2AExpr where

  ----------------------------------------------------

  const _ x = C2AExpr $ \ _ ->

    A.Const x

  ----------------------------------------------------

  drop t i id = C2AExpr $ \ meta ->

    let
      Just strmInfo = M.lookup id (streamInfoMap meta)
    in
      drop1 t strmInfo

    where

    drop1 :: C.Type α -> StreamInfo -> A.E α
    drop1 t1
      StreamInfo
        { streamInfoBufferArray = arr
        , streamInfoBufferIndex = idx
        , streamInfoBufferSize  = sz
        , streamInfoType        = t2
        } =
      let
        Just p = (=~=) t2 t1
        k = fromIntegral i
        m = (value idx + k + 1) `mod_` sz
      in
        case exprInst t2 of
          ExprInst ->
            coerce (cong p) (arr !. m)

  ----------------------------------------------------

  extern t cs = C2AExpr $ \ _ ->

    (A.value . A.var' cs . c2aType) t

  ----------------------------------------------------

  op1 op e = C2AExpr $ \ meta ->

    let
      e' = c2aExpr_ e meta
    in
      c2aOp1 op e'

  ----------------------------------------------------

  op2 op e1 e2 = C2AExpr $ \ meta ->

    let
      e1' = c2aExpr_ e1 meta
      e2' = c2aExpr_ e2 meta
    in
      c2aOp2 op e1' e2'

  ----------------------------------------------------

  op3 op e1 e2 e3 = C2AExpr $ \ meta ->

    let
      e1' = c2aExpr_ e1 meta
      e2' = c2aExpr_ e2 meta
      e3' = c2aExpr_ e3 meta
    in
      c2aOp3 op e1' e2' e3'

  ----------------------------------------------------

instance C.Op1 C2AOp1 where
  not    = C2AOp1 $                                          A.not_
  abs  t = C2AOp1 $ case numEInst      t of NumEInst      -> abs
  sign t = C2AOp1 $ case numEInst      t of NumEInst      -> signum

instance C.Op2 C2AOp2 where
  and    = C2AOp2 $                                          (A.&&.)
  or     = C2AOp2 $                                          (A.||.)
  add t  = C2AOp2 $ case numEInst      t of NumEInst      -> (+)
  sub t  = C2AOp2 $ case numEInst      t of NumEInst      -> (-)
  mul t  = C2AOp2 $ case numEInst      t of NumEInst      -> (*)
  div t  = C2AOp2 $ case integralEInst t of IntegralEInst -> A.div_
  mod t  = C2AOp2 $ case integralEInst t of IntegralEInst -> A.mod_
  eq t   = C2AOp2 $ case eqEInst       t of EqEInst       -> (A.==.)
  ne t   = C2AOp2 $ case eqEInst       t of EqEInst       -> (A./=.)
  le t   = C2AOp2 $ case ordEInst      t of OrdEInst      -> (A.<=.)
  ge t   = C2AOp2 $ case ordEInst      t of OrdEInst      -> (A.>=.)
  lt t   = C2AOp2 $ case ordEInst      t of OrdEInst      -> (A.<.)
  gt t   = C2AOp2 $ case ordEInst      t of OrdEInst      -> (A.>.)


instance C.Op3 C2AOp3 where
  mux t  = C2AOp3 $ case exprInst      t of ExprInst      -> A.mux

--------------------------------------------------------------------------------