module Data.Vec where

open import Level
open import Data.Nat
open import Data.Product
open import Function

private variable
  a : Level
  A B : Set a
  n : Nat

data Vec {a} (A : Set a) : Nat → Set a where
  [] : Vec A 0
  _∷_ : ∀ {n} → A → Vec A n → Vec A (suc n)

{-# COMPILE JS [] = [] #-}
{-# COMPILE JS _∷_ = _ => x => xs => [x, ...xs]  #-}

unsnoc : Vec A (suc n) → Vec A n × A
unsnoc (a ∷ []) = [] , a
unsnoc (a ∷ as@(_ ∷ _)) = let (as' , a') = unsnoc as in a ∷ as' , a'
{-# COMPILE JS unsnoc = a => A => n => xs => {
  return { "_,_": y => y["_,_"](xs.slice(0, xs.length - 1), xs[xs.length - 1]) };
} #-}

map : (A → B) → Vec A n → Vec B n
map f [] = []
map f (x ∷ xs) = f x ∷ map f xs
{-# COMPILE JS map = a => A => b => B => f => as => as.map(a => f(a)) #-}