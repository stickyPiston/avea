module Data.Product where

open import Agda.Builtin.Sigma
  renaming (fst to proj₁ ; snd to proj₂) public
open import Level

_×_ : ∀ {a b} → Set a → Set b → Set (a ⊔ b)
A × B = Σ A λ _ → B

map-first : ∀ {A B C : Set} → (A → B) → A × C → B × C
map-first f (a , b) = f a , b

map-second : ∀ {A B C : Set} → (B → C) → A × B → A × C
map-second f (a , b) = a , f b