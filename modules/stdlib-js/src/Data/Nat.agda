module Data.Nat where

open import Agda.Builtin.Nat hiding (_<_) public
open import Data.Bool
open import Data.Product

ℕ : Set
ℕ = Nat

postulate ⌊_/_⌋ : ℕ → ℕ → ℕ
{-# COMPILE JS ⌊_/_⌋ = a => b => a / b #-}

_mod_ : ℕ → ℕ → ℕ
a mod b = a - ⌊ a / b ⌋ * b

_quot-rem_ : ℕ → ℕ → ℕ × ℕ
a quot-rem b = ⌊ a / b ⌋ , a mod b
