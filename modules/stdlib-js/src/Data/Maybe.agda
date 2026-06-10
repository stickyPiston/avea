module Data.Maybe where

open import Agda.Primitive
open import Agda.Builtin.Maybe public
open import Agda.Builtin.Bool

private variable
  ℓ ℓ₁ ℓ₂ : Level
  A B C : Set ℓ
  F : Set ℓ₁ → Set ℓ₂

from-Maybe : A → Maybe A → A
from-Maybe b nothing  = b
from-Maybe _ (just a) = a

_or-else_ : Maybe A → A → A
nothing or-else a = a
just a or-else _ = a

maybe : B → (A → B) → Maybe A → B
maybe b _ nothing  = b
maybe _ f (just a) = f a

is-just : Maybe A → Bool
is-just nothing = false
is-just (just _) = true

postulate from-just : Maybe A → A
{-# COMPILE JS from-just = a => A => m => m({ "just": x => x, "nothing": () => { throw new Error("from-just") } }) #-}