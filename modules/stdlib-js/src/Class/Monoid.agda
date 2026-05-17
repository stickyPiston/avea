module Class.Monoid where

open import Level
open import Data.List
open import Data.Maybe
open import Data.String
open import Data.Map

private variable
  a : Level
  A : Set a

module _ where
  record Semigroup (A : Set a) : Set a where
    field _<>_ : A → A → A

    infixr 10 _<>_
  open Semigroup {{ ... }}

  private
    combine-Maybe : {{ Semigroup A }} → Maybe A → Maybe A → Maybe A
    combine-Maybe {{ s }} (just a) (just b) = just (a <> b)
    combine-Maybe _ _ = nothing

  instance
    Semigroup-Maybe : {{ Semigroup A }} → Semigroup (Maybe A)
    Semigroup-Maybe = record { _<>_ = combine-Maybe }

  private
    combine-List : List A → List A → List A
    combine-List = append
  
  instance
    Semigroup-List : Semigroup (List A)
    Semigroup-List = record { _<>_ = combine-List }

  instance
    Semigroup-String : Semigroup String
    Semigroup-String = record { _<>_ = primStringAppend }

  instance
    Semigroup-StringMap : Semigroup (StringMap.t A)
    Semigroup-StringMap = record { _<>_ = StringMap.combine }

module _ where
  record Monoid (A : Set a) : Set a where
    field
      semigroup : Semigroup A
      empty : A

    open Semigroup semigroup public
  open Monoid {{ ... }}

  mconcat : {{ Monoid A }} → List A → A
  mconcat = foldr empty _<>_

  instance
    Monoid-Maybe : {{ Semigroup A }} → Monoid (Maybe A)
    Monoid-Maybe = record { semigroup = Semigroup-Maybe ; empty = nothing }

    Monoid-List : Monoid (List A)
    Monoid-List = record { semigroup = Semigroup-List ; empty = [] }
    
    Monoid-String : Monoid String
    Monoid-String = record { semigroup = Semigroup-String ; empty = "" }

    Monoid-StringMap : Monoid (StringMap.t A)
    Monoid-StringMap = record { semigroup = Semigroup-StringMap ; empty = StringMap.empty }

open Semigroup {{ ... }} hiding (_<>_) public
open Monoid {{ ... }} public