module Class.Show where

open import Data.String
open import Data.Nat
open import Data.Int
open import Data.Bool
open import Data.List
open import Data.Maybe
open import Data.Product

open import Class.Monoid

private variable
  A B : Set

record Show (A : Set) : Set where field
  show : A → String
open Show {{ ... }} public

instance
  Show-String : Show String
  Show-String = record { show = primShowString }

  Show-Nat : Show Nat
  Show-Nat = record { show = primShowNat }

  Show-Int : Show Int
  Show-Int = record
    { show = λ where
        (pos n) → show n
        (negsuc n) → "-" <> show (suc n)
    }

  Show-Bool : Show Bool
  Show-Bool = record { show = λ { true → "true" ; false → "false" } }

private
  show-List : {{ Show A }} → List A → String
  show-List xs = "[" <> intercalate ", " (map show xs) <> "]"

instance
  Show-List : {A : Set} → {{ Show A }} → Show (List A)
  Show-List = record { show = show-List }

private
  show-Maybe : {{ Show A }} → Maybe A → String
  show-Maybe (just a) = "just " <> show a
  show-Maybe nothing  = "nothing"

instance
  Show-Maybe : {A : Set} → {{ Show A }} → Show (Maybe A)
  Show-Maybe = record { show = show-Maybe }

private
  show-× : {{ Show A }} → {{ Show B }} → A × B → String
  show-× (a , b) = show a <> " , " <> show b

instance
  Show-× : {{ Show A }} → {{ Show B }} → Show (A × B)
  Show-× = record { show = show-× }