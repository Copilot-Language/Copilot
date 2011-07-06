--------------------------------------------------------------------------------
-- Copyright © 2011 National Institute of Aerospace / Galois, Inc.
--------------------------------------------------------------------------------

{-# LANGUAGE Rank2Types #-}

module Copilot.Core.Expr
  ( Id
  , Name
  , Expr (..)
  , WrapExpr (..)
  , DropIdx
  ) where

import Copilot.Core.Operators (Op1, Op2, Op3)
import Copilot.Core.Type (Type)
import Data.Word (Word8)

--------------------------------------------------------------------------------

-- | A stream identifier.
type Id = Int

--------------------------------------------------------------------------------

-- | A name of a trigger, an external variable, or an external function.
type Name = String

--------------------------------------------------------------------------------

type DropIdx = Word8

--------------------------------------------------------------------------------

-- | The expression class.
class Expr e where
  -- | A constant.
  const
    :: Type a
    -> a
    -> e a
  -- | The temporal look-ahead operator.
  drop
    :: Type a
    -> DropIdx
    -> Id
    -> e a
  -- | A binding of local variable.
  local
    :: Type a
    -> Type b
    -> Name
    -> e a
    -> e b
    -> e b
  -- | A bound local variable.
  var
    :: Type a
    -> Name
    -> e a
  extern
    :: Type a
    -> Name
    -> e a
  -- | An unary operator.
  op1
    :: (forall op . Op1 op => op a b)
    -> e a -> e b
  -- | A binary operator.
  op2
    :: (forall op . Op2 op => op a b c)
    -> e a -> e b -> e c
  -- | A Ternary operator.
  op3
    :: (forall op . Op3 op => op a b c d)
    -> e a -> e b -> e c -> e d

--------------------------------------------------------------------------------

-- A wrapped expression.

data WrapExpr a = WrapExpr { unWrapExpr :: forall e . Expr e => e a }

--------------------------------------------------------------------------------
