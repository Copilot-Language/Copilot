--------------------------------------------------------------------------------
-- Copyright © 2011 National Institute of Aerospace / Galois, Inc.
--------------------------------------------------------------------------------

-- | A pretty printer for Copilot specifications.

{-# LANGUAGE GADTs #-}

module Copilot.Core.PrettyPrint
  ( prettyPrint
  ) where

import Copilot.Core
import Copilot.Core.Type.Show (showWithType, ShowType(..), showType)
import Prelude hiding (id)
import Text.PrettyPrint.HughesPJ
import Data.List (intersperse)

--------------------------------------------------------------------------------

ppExpr :: Expr a -> Doc
ppExpr e0 = case e0 of
  Const t x            -> text (showWithType Haskell t x)
  Drop _ 0 id          -> text "stream" <+> text "s" <> int id
  Drop _ i id          -> text "drop" <+> text (show i) <+> text "s" <>
                          int id
  ExternVar _ name     -> text "extern \"" <> text name <> text "\""
  Local _ _ name e1 e2 -> text "local \"" <> text name <> text "\" ="
                                    <+> ppExpr e1 $$ text "in" <+> ppExpr e2
  Var _ name           -> text "var \"" <> text name <> text "\""
  Op1 op e             -> ppOp1 op (ppExpr e)
  Op2 op e1 e2         -> ppOp2 op (ppExpr e1) (ppExpr e2)
  Op3 op e1 e2 e3      -> ppOp3 op (ppExpr e1) (ppExpr e2) (ppExpr e3)
  _                    -> error "Expression not implemented in PrettyPrint.hs in copilot-core!"

ppOp1 :: Op1 a b -> Doc -> Doc
ppOp1 op = case op of
  Not      -> ppPrefix "not"
  Abs _    -> ppPrefix "abs"
  Sign _   -> ppPrefix "signum"
  Recip _  -> ppPrefix "recip"
  Exp _    -> ppPrefix "exp"
  Sqrt _   -> ppPrefix "sqrt"
  Log _    -> ppPrefix "log"
  Sin _    -> ppPrefix "sin"
  Tan _    -> ppPrefix "tan"
  Cos _    -> ppPrefix "cos"
  Asin _   -> ppPrefix "asin"
  Atan _   -> ppPrefix "atan"
  Acos _   -> ppPrefix "acos"
  Sinh _   -> ppPrefix "sinh"
  Tanh _   -> ppPrefix "tanh"
  Cosh _   -> ppPrefix "cosh"
  Asinh _  -> ppPrefix "asinh"
  Atanh _  -> ppPrefix "atanh"
  Acosh _  -> ppPrefix "acosh"
  BwNot _  -> ppPrefix "~"

ppOp2 :: Op2 a b c -> Doc -> Doc -> Doc
ppOp2 op = case op of
  And          -> ppInfix "&&"
  Or           -> ppInfix "||"
  Add      _   -> ppInfix "+"
  Sub      _   -> ppInfix "-"
  Mul      _   -> ppInfix "*"
  Div      _   -> ppInfix "div"
  Mod      _   -> ppInfix "mod"
  Fdiv     _   -> ppInfix "/"
  Pow      _   -> ppInfix "**"
  Logb     _   -> ppInfix "logBase"
  Eq       _   -> ppInfix "=="
  Ne       _   -> ppInfix "/="
  Le       _   -> ppInfix "<="
  Ge       _   -> ppInfix ">="
  Lt       _   -> ppInfix "<"
  Gt       _   -> ppInfix ">"
  BwAnd    _   -> ppInfix "&"
  BwOr     _   -> ppInfix "|"
  BwXor    _   -> ppInfix "^"
  BwShiftL _ _ -> ppInfix "<<"
  BwShiftR _ _ -> ppInfix ">>"

ppOp3 :: Op3 a b c d -> Doc -> Doc -> Doc -> Doc
ppOp3 op = case op of
  Mux _    -> \ doc1 doc2 doc3 ->
    text "(if"   <+> doc1 <+>
    text "then" <+> doc2 <+>
    text "else" <+> doc3 <> text ")"

--------------------------------------------------------------------------------
  
ppInfix :: String -> Doc -> Doc -> Doc
ppInfix cs doc1 doc2 = parens $ doc1 <+> text cs <+> doc2

ppPrefix :: String -> Doc -> Doc
ppPrefix cs = (text cs <+>)

--------------------------------------------------------------------------------

ppStream :: Stream -> Doc
ppStream
  Stream
    { streamId       = id
    , streamBuffer   = buffer
    , streamExpr     = e
    , streamExprType = t
    }
      = (parens . text . showType) t
          <+> text "strm: \"s" <> int id <> text "\""
    <+> text "="
    <+> text ("["
              ++ ( concat $ intersperse "," 
                              $ map (showWithType Haskell t) buffer )
              ++ "]")
    <+> text "++"
    <+> ppExpr e

--------------------------------------------------------------------------------

ppTrigger :: Trigger -> Doc
ppTrigger
  Trigger
    { triggerName  = name
    , triggerGuard = e
    , triggerArgs  = args }
  =   text "trigger: \"" <> text name <> text "\""
  <+> text "="
  <+> ppExpr e
  $$  nest 2 (foldr (($$) . ppUExpr) empty argsAndNum)

  where

  argsAndNum :: [(UExpr, Int)]
  argsAndNum = zip args [0..]

  ppUExpr :: (UExpr, Int) -> Doc
  ppUExpr (UExpr _ e1, k)
    =   text "arg: " <> int k
    <+> text "="
    <+> ppExpr e1

--------------------------------------------------------------------------------

ppObserver :: Observer -> Doc
ppObserver
  Observer
    { observerName     = name
    , observerExpr     = e }
  =   text "observer: \"" <> text name <> text "\""
  <+> text "="
  <+> ppExpr e

--------------------------------------------------------------------------------

ppSpec :: Spec -> Doc
ppSpec spec = cs $$ ds $$ es
  where
    cs = foldr (($$) . ppStream)   empty (specStreams   spec)
    ds = foldr (($$) . ppTrigger)  empty (specTriggers  spec)
    es = foldr (($$) . ppObserver) empty (specObservers spec)

--------------------------------------------------------------------------------

-- | Pretty-prints a Copilot specification.
prettyPrint :: Spec -> String
prettyPrint = render . ppSpec

--------------------------------------------------------------------------------
