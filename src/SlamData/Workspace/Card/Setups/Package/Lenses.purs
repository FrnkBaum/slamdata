{-
Copyright 2017 SlamData, Inc.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
-}

module SlamData.Workspace.Card.Setups.Package.Lenses where

import Data.Lens (Lens, lens)

_open ∷ ∀ a b r. Lens { open ∷ a | r } { open ∷ b | r } a b
_open = lens _.open _{ open = _ }

_close ∷ ∀ a b r. Lens { close ∷ a | r } { close ∷ b | r } a b
_close = lens _.close _{ close = _ }

_high ∷ ∀ a b r. Lens { high ∷ a | r } { high ∷ b | r } a b
_high = lens _.high _{ high = _ }

_low ∷ ∀ a b r. Lens { low ∷ a | r } { low ∷ b | r } a b
_low = lens _.low _{ low = _ }

_dimension ∷ ∀ a b r. Lens { dimension ∷ a | r } { dimension ∷ b | r } a b
_dimension = lens _.dimension _{ dimension = _ }

_parallel ∷ ∀ a b r. Lens { parallel ∷ a | r } { parallel ∷ b | r } a b
_parallel = lens _.parallel _{ parallel = _ }

_value ∷ ∀ a b r. Lens { value ∷ a | r } { value ∷ b | r } a b
_value = lens _.value _{ value = _ }

_series ∷ ∀ a b r. Lens { series ∷ a | r } { series ∷ b | r } a b
_series = lens _.series _{ series = _ }

_category ∷ ∀ a b r. Lens { category ∷ a | r } { category ∷ b | r } a b
_category = lens _.category _{ category = _ }

_stack ∷ ∀ a b r. Lens { stack ∷ a | r } { stack ∷ b | r } a b
_stack = lens _.stack _{ stack = _ }

_multiple ∷ ∀ a b r. Lens { multiple ∷ a | r } { multiple ∷ b | r } a b
_multiple = lens _.multiple _{ multiple = _ }

_source ∷ ∀ a b r. Lens { source ∷ a | r } { source ∷ b | r } a b
_source = lens _.source _{ source = _ }

_target ∷ ∀ a b r. Lens { target ∷ a | r } { target ∷ b | r } a b
_target = lens _.target _{ target = _ }

_abscissa ∷ ∀ a b r. Lens { abscissa ∷ a | r } { abscissa ∷ b | r } a b
_abscissa = lens _.abscissa _{ abscissa = _ }

_ordinate ∷ ∀ a b r. Lens { ordinate ∷ a | r } { ordinate ∷ b | r } a b
_ordinate = lens _.ordinate _{ ordinate = _ }

_secondValue ∷ ∀ a b r. Lens { secondValue ∷ a | r } { secondValue ∷ b | r } a b
_secondValue = lens _.secondValue _{ secondValue = _ }

_donut ∷ ∀ a b r. Lens { donut ∷ a | r } { donut ∷ b | r } a b
_donut = lens _.donut _{ donut = _ }

_size ∷ ∀ a b r. Lens { size ∷ a | r } { size ∷ b | r } a b
_size = lens _.size _{ size = _ }

_color ∷ ∀ a b r. Lens { color ∷ a | r } { color ∷ b | r } a b
_color = lens _.color _{ color = _ }

_lat ∷ ∀ a b r. Lens { lat ∷ a | r } { lat ∷ b | r } a b
_lat = lens _.lat _{ lat = _ }

_lng ∷ ∀ a b r. Lens { lng ∷ a | r } { lng ∷ b | r } a b
_lng = lens _.lng _{ lng = _ }

_intensity ∷ ∀ a b r. Lens { intensity ∷ a | r } { intensity ∷ b | r } a b
_intensity = lens _.intensity _{ intensity = _ }
