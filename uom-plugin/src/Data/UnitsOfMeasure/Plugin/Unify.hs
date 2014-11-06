module Data.UnitsOfMeasure.Plugin.Unify
  ( UnifyResult(..)
  , TySubst
  , SubstItem(..)
  , unifyUnits
  ) where

import Outputable
import TcRnTypes
import Type
import TypeRep

import Data.UnitsOfMeasure.Plugin.Convert
import Data.UnitsOfMeasure.Plugin.NormalForm
import TcPluginExtras


data UnifyResult = Win [TyVar] TySubst | Lose | Draw [TyVar] TySubst

instance Outputable UnifyResult where
  ppr (Win  tvs subst) = text "Win"  <+> ppr tvs <+> ppr subst
  ppr (Draw tvs subst) = text "Draw" <+> ppr tvs <+> ppr subst
  ppr Lose             = text "Lose"

type TySubst = [SubstItem]

data SubstItem = SubstItem { siVar     :: TyVar
                           , siUnit    :: NormUnit
                           , siCt     ::  Ct
                           }

instance Outputable SubstItem where
  ppr si = ppr (siVar si) <+> text " := " <+> ppr (siUnit si)


unifyUnits :: UnitDefs -> Ct -> NormUnit -> NormUnit -> TcPluginM UnifyResult
unifyUnits uds ct u0 v0 = do tcPluginTrace "unifyUnits" (ppr u0 $$ ppr v0)
                             unifyOne uds ct [] [] (u0 /: v0)

unifyOne :: UnitDefs -> Ct -> [TyVar] -> TySubst -> NormUnit -> TcPluginM UnifyResult
unifyOne uds ct tvs subst u
      | isOne u           = return $ Win tvs subst
      | isConstant u      = return   Lose
      | otherwise         = tcPluginTrace "unifyOne" (ppr u) >> go [] (ascending u)

      where
        go :: [(Atom, Integer)] -> [(Atom, Integer)] -> TcPluginM UnifyResult
        go _  []                       = return $ Draw tvs subst
        go ls (at@(VarAtom a, i) : xs) =
            case () of
                () | divisible i u -> let r = divideExponents (-i) $ leftover a u
                                             in return $ Win tvs $ SubstItem a r ct : subst
                   | any (not . isBase . fst) xs -> do TyVarTy beta <- newFlexiTyVarTy $ unitKind uds
                                                       let r = atom (VarAtom beta) *: divideExponents (-i) (leftover a u)
                                                       unifyOne uds ct (beta:tvs) (SubstItem a r ct:subst) $ substUnit a r u
                   | otherwise            -> go (at:ls) xs

        go ls (at@(FamAtom f tys, i) : xs) = do
          mb <- matchFam f tys
          case mb of
            Just (_, ty)
              | Just v <- normaliseUnit uds ty -> unifyOne uds ct tvs subst $ mkNormUnit (ls ++ xs) *: v ^: i
              | otherwise                  -> error "help help help help" -- TODO
            Nothing                        -> go (at:ls) xs -- TODO: more we can do here?
        go ls (at@(BaseAtom  _, _) : xs) = go (at:ls) xs
