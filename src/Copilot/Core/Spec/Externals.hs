--------------------------------------------------------------------------------
-- Copyright © 2011 National Institute of Aerospace / Galois, Inc.
--------------------------------------------------------------------------------

{-# LANGUAGE ExistentialQuantification #-}

-- | 

module Copilot.Core.Spec.Externals
  ( Extern (..)
  , externals
  ) where

import Copilot.Core
import Data.DList (DList, empty, singleton, append, concat, toList)
import Data.List (nubBy)
import Prelude hiding (concat, foldr)

--------------------------------------------------------------------------------

data Extern = forall a . Extern
  { externName :: Name
  , externType :: Type a }

--------------------------------------------------------------------------------

externals :: Spec -> [Extern]
externals
  Spec
    { specStreams   = streams
    , specTriggers  = triggers
    , specObservers = observers } =
  nubBy eqExt . toList $
    concat (fmap extsStream   streams)  `append`
    concat (fmap extsTrigger  triggers) `append`
    concat (fmap extsObserver observers)

  where

  eqExt :: Extern -> Extern -> Bool
  eqExt Extern { externName = name1 } Extern { externName = name2 } =
    name1 == name2

--------------------------------------------------------------------------------

extsStream :: Stream -> DList Extern
extsStream Stream { streamExpr = e } = extsExpr e

--------------------------------------------------------------------------------

extsTrigger :: Trigger -> DList Extern
extsTrigger Trigger { triggerGuard = e, triggerArgs = args } =
  extsExpr e `append` concat (fmap extsUExpr args)

  where

  extsUExpr :: UExpr -> DList Extern
  extsUExpr (UExpr _ e1) = extsExpr e1

--------------------------------------------------------------------------------

extsObserver :: Observer -> DList Extern
extsObserver Observer { observerExpr = e } = extsExpr e

--------------------------------------------------------------------------------

newtype ExtsExpr a = ExtsExpr { extsExpr :: DList Extern }

instance Expr ExtsExpr where
  const  _ _        = ExtsExpr $ empty
  drop   _ _ _      = ExtsExpr $ empty
  local _ _ _ e1 e2 = ExtsExpr $ extsExpr e1 `append` extsExpr e2
  var _ _           = ExtsExpr $ empty
  extern t name     = ExtsExpr $ singleton (Extern name t)
  op1 _ e           = ExtsExpr $ extsExpr e
  op2 _ e1 e2       = ExtsExpr $ extsExpr e1 `append` extsExpr e2
  op3 _ e1 e2 e3    = ExtsExpr $ extsExpr e1 `append` extsExpr e2
                                             `append` extsExpr e3

--------------------------------------------------------------------------------
