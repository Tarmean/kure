-- |
-- Module: Language.KURE.Translate
-- Copyright: (c) 2012 The University of Kansas
-- License: BSD3
--
-- Maintainer: Neil Sculthorpe <neil@ittc.ku.edu>
-- Stability: beta
-- Portability: ghc
--
-- This module defines the main KURE types: 'Translate', 'Rewrite' and 'Lens'.
-- 'Rewrite' and 'Lens' are just special cases of 'Translate', and so any function that operates on 'Translate' is also
-- applicable to 'Rewrite' and 'Lens' (although care should be taken in the 'Lens' case).
--
-- This module also contains 'Translate' instance declarations for the 'Monad' and 'Arrow' type-class families.
-- Given these instances, many of the desirable combinators over 'Translate' and 'Rewrite' are special cases
-- of existing monadic or arrow combinators.
-- "Language.KURE.Combinators" provides some additional combinators that aren't in the standard libraries.

module Language.KURE.Translate
       (  -- * Translations
          Translate(..)
        , Rewrite
        , translate
        , rewrite
        , contextfreeT
        , constT
        , contextT
        , exposeT
        , mapT
          -- * Lenses
        , Lens
        , lens
        , idL
        , tryL
        , composeL
        , sequenceL
        , pureL
        , focusR
        , focusT
        , sideEffectR

) where

import Prelude hiding (id, (.))
import Control.Applicative
import Control.Monad
import Control.Category
import Control.Arrow
import Data.Monoid

------------------------------------------------------------------------------------------

-- | 'Translate' is a translation or strategy that translates from a value in a context to a monadic value.
data Translate c m a b = Translate { -- | Apply a 'Translate' to a value and its context.
                                     apply :: c -> a -> m b}

-- | A 'Rewrite' is a 'Translate' that shares the same source and target type.
type Rewrite c m a = Translate c m a a

-- | The primitive  way of building a 'Translate'.
translate :: (c -> a -> m b) -> Translate c m a b
translate = Translate

-- | The primitive way of building a 'Rewrite'.
rewrite :: (c -> a -> m a) -> Rewrite c m a
rewrite = translate

------------------------------------------------------------------------------------------

-- | Build a 'Translate' that doesn't depend on the context.
contextfreeT :: (a -> m b) -> Translate c m a b
contextfreeT = translate . const

-- | Build a constant 'Translate' from a monadic computation.
constT :: m b -> Translate c m a b
constT = contextfreeT . const

-- | Extract the current context.
contextT :: Monad m => Translate c m a c
contextT = translate (\ c _ -> return c)

-- | Expose the current context and value.
exposeT :: Monad m => Translate c m a (c,a)
exposeT = translate (curry return)

-- | Map a 'Translate' over a list.
mapT :: Monad m => Translate c m a b -> Translate c m [a] [b]
mapT t = translate (mapM . apply t)

-- | An identity 'Rewrite' with side-effects.
sideEffectR :: Monad m => m x -> Rewrite c m a
sideEffectR mx = constT mx >> id

------------------------------------------------------------------------------------------

-- | Lifting through a Reader transformer, where (c,a) is the read-only environment.
instance Functor m => Functor (Translate c m a) where

-- fmap :: (b -> d) -> Translate c m a b -> Translate c m a d
   fmap f t = translate (\ c -> fmap f . apply t c)

-- | Lifting through a Reader transformer, where (c,a) is the read-only environment.
instance Applicative m => Applicative (Translate c m a) where

-- pure :: b -> Translate c m a b
   pure = constT . pure

-- (<*>) :: Translate c m a (b -> d) -> Translate c m a b -> Translate c m a d
   tf <*> tb = translate (\ c a -> apply tf c a <*> apply tb c a)

-- | Lifting through a Reader transformer, where (c,a) is the read-only environment.
instance Alternative m => Alternative (Translate c m a) where

-- empty :: Translate c m a b
   empty = constT empty

-- (<|>) :: Translate c m a b -> Translate c m a b -> Translate c m a b
   t1 <|> t2 = translate $ \ c a -> apply t1 c a <|> apply t2 c a

-- | Lifting through a Reader transformer, where (c,a) is the read-only environment.
instance Monad m => Monad (Translate c m a) where

-- return :: b -> Translate c m a b
   return = constT . return

-- (>>=) :: Translate c m a b -> (b -> Translate c m a d) -> Translate c m a d
   t >>= f = translate $ \ c a -> do b <- apply t c a
                                     apply (f b) c a

-- fail :: String -> Translate c m a b
   fail = constT . fail

-- | Lifting through a Reader transformer, where (c,a) is the read-only environment.
instance MonadPlus m => MonadPlus (Translate c m a) where

-- mzero :: Translate c m a b
   mzero = constT mzero

-- mplus :: Translate c m a b -> Translate c m a b -> Translate c m a b
   mplus t1 t2 = translate $ \ c a -> apply t1 c a `mplus` apply t2 c a

-- | The 'Kleisli' 'Category' induced by @m@, lifting through a Reader transformer, where @c@ is the read-only environment.
instance Monad m => Category (Translate c m) where

--  id :: Translate c m a a
    id = contextfreeT return

--  (.) :: Translate c m b d -> Translate c m a b -> Translate c m a d
    t2 . t1 = translate $ \ c -> apply t1 c >=> apply t2 c

-- | The 'Kleisli' 'Arrow' induced by @m@, lifting through a Reader transformer, where @c@ is the read-only environment.
instance Monad m => Arrow (Translate c m) where

-- arr :: (a -> b) -> Translate c m a b
   arr f = contextfreeT (return . f)

-- first :: Translate c m a b -> Translate c m (a,z) (b,z)
   first t = translate $ \ c (a,z) -> liftM (\b -> (b,z)) (apply t c a)

-- (***) :: Translate c m a1 b1 -> Translate c m a2 b2 -> Translate c m (a1,a2) (b1,b2)
   t1 *** t2 = translate $ \ c (a,b) -> liftM2 (,) (apply t1 c a) (apply t2 c b)

-- (&&&) :: Translate c m a b1 -> Translate c m a b2 -> Translate c m a (b1,b2)
   t1 &&& t2 = translate $ \ c a -> liftM2 (,) (apply t1 c a) (apply t2 c a)

-- | The 'Kleisli' 'Arrow' induced by @m@, lifting through a Reader transformer, where @c@ is the read-only environment.
instance MonadPlus m => ArrowZero (Translate c m) where

-- zeroArrow :: Translate c m a b
   zeroArrow = mzero

-- | The 'Kleisli' 'Arrow' induced by @m@, lifting through a Reader transformer, where @c@ is the read-only environment.
instance MonadPlus m => ArrowPlus (Translate c m) where

-- (<+>) :: Translate c m a b -> Translate c m a b -> Translate c m a b
   (<+>) = mplus

-- | The 'Kleisli' 'Arrow' induced by @m@, lifting through a Reader transformer, where @c@ is the read-only environment.
instance Monad m => ArrowApply (Translate c m) where

-- app :: Translate c m (Translate c m a b, a) b
   app = translate $ \ c (t,a) -> apply t c a

-- | Lifting through the 'Monad' and a Reader transformer, where (c,a) is the read-only environment.
instance (Monad m, Monoid b) => Monoid (Translate c m a b) where

-- mempty :: Translate c m a b
   mempty = return mempty

-- mappend :: Translate c m a b -> Translate c m a b -> Translate c m a b
   mappend = liftM2 mappend

------------------------------------------------------------------------------------------

-- | A 'Lens' is a way to focus in on a particular point in a structure.
type Lens c m a b = Translate c m a ((c,b), b -> m a)

-- | 'lens' is the primitive way of building a 'Lens'.
lens :: (c -> a -> m ((c,b), b -> m a)) -> Lens c m a b
lens = translate

-- | Identity 'Lens'.
idL :: Monad m => Lens c m a a
idL = lens $ \ c a -> return ((c,a), return)

-- | Catch a failing endo'Lens', making it into an identity.
tryL :: MonadPlus m => Lens c m a a -> Lens c m a a
tryL l = l <+> idL

-- | Composition of 'Lens's.
composeL :: Monad m => Lens c m a b -> Lens c m b d -> Lens c m a d
composeL l1 l2 = lens $ \ ca a -> do ((cb,b),kb) <- apply l1 ca a
                                     ((cd,d),kd) <- apply l2 cb b
                                     return ((cd,d),kd >=> kb)

-- | Sequence a list of endo'Lens's.
sequenceL :: MonadPlus m => [Lens c m a a] -> Lens c m a a
sequenceL = foldr composeL idL

-- | Construct a 'Lens' from two pure functions.
pureL :: Monad m => (a -> b) -> (b -> a) -> Lens c m a b
pureL f g = lens (\ c a -> return ((c,f a), return . g))

-- | Apply a 'Rewrite' at a point specified by a 'Lens'.
focusR :: Monad m => Lens c m a b -> Rewrite c m b -> Rewrite c m a
focusR l r = rewrite $ \ c a -> do ((c',b),k) <- apply l c a
                                   apply r c' b >>= k

-- | Apply a 'Translate' at a point specified by a 'Lens'.
focusT :: Monad m => Lens c m a b -> Translate c m b d -> Translate c m a d
focusT l t = translate $ \ c a -> do ((c',b),_) <- apply l c a
                                     apply t c' b

------------------------------------------------------------------------------------------
