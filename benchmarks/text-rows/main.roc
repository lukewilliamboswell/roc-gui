app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }

import pf.Action
import pf.Elem exposing [Elem]
import pf.Layout
import pf.Program exposing [Program]

Content : [Short, Long, MetadataRich]
State : { count : U64, content : Content }

body : Content -> Str
body = |content| match content {
	Short => "Ready"
	Long => "A realistic notification body can contain enough detail to wrap over several lines, including context about the operation, its outcome, and the next action available to the reader."
	MetadataRich => "Ready"
}

render_message : U64, Content -> Elem(State)
render_message = |id, content| {
	primary = [Elem.text("Message ${id.to_str()}"), Elem.text("Body: ${body(content)}")]
	metadata = match content {
		MetadataRich => [Elem.text("Author: Operator"), Elem.text("Status: Delivered"), Elem.text("Received: just now")]
		_ => []
	}
	Layout.col({}, primary.concat(metadata))
}

render : State -> Elem(State)
render = |state| {
	var $messages = []
	for _ in List.repeat({}, state.count) {
		id = $messages.len() + 1
		$messages = $messages.append(render_message(id, state.content))
	}
	Layout.col({}, [
		Layout.row({}, [
			Elem.button({ label: Elem.text("Short 100"), name: "Show 100 short messages", on_press: |_, _| Action.update({ count: 100, content: Short }) }),
			Elem.button({ label: Elem.text("Short 1,000"), name: "Show 1,000 short messages", on_press: |_, _| Action.update({ count: 1000, content: Short }) }),
			Elem.button({ label: Elem.text("Short 10,000"), name: "Show 10,000 short messages", on_press: |_, _| Action.update({ count: 10000, content: Short }) }),
			Elem.button({ label: Elem.text("Long 100"), name: "Show 100 long messages", on_press: |_, _| Action.update({ count: 100, content: Long }) }),
			Elem.button({ label: Elem.text("Long 1,000"), name: "Show 1,000 long messages", on_press: |_, _| Action.update({ count: 1000, content: Long }) }),
			Elem.button({ label: Elem.text("Long 10,000"), name: "Show 10,000 long messages", on_press: |_, _| Action.update({ count: 10000, content: Long }) }),
			Elem.button({ label: Elem.text("Rich 100"), name: "Show 100 metadata-rich messages", on_press: |_, _| Action.update({ count: 100, content: MetadataRich }) }),
			Elem.button({ label: Elem.text("Rich 1,000"), name: "Show 1,000 metadata-rich messages", on_press: |_, _| Action.update({ count: 1000, content: MetadataRich }) }),
			Elem.button({ label: Elem.text("Rich 10,000"), name: "Show 10,000 metadata-rich messages", on_press: |_, _| Action.update({ count: 10000, content: MetadataRich }) }),
		]),
		Layout.col({}, $messages),
	])
}

main : Program(State)
main = Program.run({ init: { count: 0, content: Short }, render })
