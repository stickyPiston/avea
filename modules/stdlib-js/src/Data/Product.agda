module Data.Product where

open import Agda.Builtin.Sigma
  renaming (fst to proj₁ ; snd to proj₂) public
open import Level

_×_ : ∀ {a b} → Set a → Set b → Set (a ⊔ b)
A × B = Σ A λ _ → B

bimap : {A B C D : Set} → (A → C) → (B → D) → A × B → C × D
bimap f g (a , b) = f a , g b
