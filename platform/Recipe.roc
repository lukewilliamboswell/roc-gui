## Pure description of startup bindings. Applications compose recipes; the
## platform interprets them. The representation is an implementation detail.
## Reusing a recipe describes another binding; reuse its resulting handle to
## share a registered definition. Composition does not compare closures.
Recipe(a) := { evaluate! : () => a }.{
	pure : a -> Recipe(a)
	pure = |value| Recipe.{ evaluate!: || value }

	map : Recipe(a), (a -> b) -> Recipe(b)
	map = |Recipe.(recipe), transform| Recipe.{ evaluate!: || transform((recipe.evaluate!)()) }

	## Record-builder composition. Evaluate each binding once, left then right.
	map2 : Recipe(a), Recipe(b), (a, b -> c) -> Recipe(c)
	map2 = |Recipe.(left), Recipe.(right), combine| Recipe.{
		evaluate!: || {
			a = (left.evaluate!)()
			b = (right.evaluate!)()
			combine(a, b)
		},
	}

	and_then : Recipe(a), (a -> Recipe(b)) -> Recipe(b)
	and_then = |Recipe.(recipe), next| Recipe.{
		evaluate!: || {
			Recipe.(result) = next((recipe.evaluate!)())
			(result.evaluate!)()
		},
	}

	## Platform interpreter entry, not an application initialization operation.
	evaluate! : Recipe(a) => a
	evaluate! = |Recipe.(recipe)| (recipe.evaluate!)()
}
