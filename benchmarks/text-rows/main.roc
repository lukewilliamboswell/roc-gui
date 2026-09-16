app [State, main] { pf: platform "../../platform/main.roc", roc: "nightly-2026-09-12-220fd47" }

import pf.Action
import pf.Elem
import pf.Program

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
	Elem.col({}, primary.concat(metadata))
}

render : State -> Elem(State)
render = |state| {
	var $messages = []
	for _ in List.repeat({}, state.count) {
		id = $messages.len() + 1
		$messages = $messages.append(render_message(id, state.content))
	}
	Elem.col(
		{},
		[
			Elem.row(
				{},
				[
					Elem.button({ caption: "Short 100", label: "Show 100 short messages", on_press: |_, _| Action.update({ count: 100, content: Short }) }),
					Elem.button({ caption: "Short 1,000", label: "Show 1,000 short messages", on_press: |_, _| Action.update({ count: 1000, content: Short }) }),
					Elem.button({ caption: "Short 10,000", label: "Show 10,000 short messages", on_press: |_, _| Action.update({ count: 10000, content: Short }) }),
					Elem.button({ caption: "Long 100", label: "Show 100 long messages", on_press: |_, _| Action.update({ count: 100, content: Long }) }),
					Elem.button({ caption: "Long 1,000", label: "Show 1,000 long messages", on_press: |_, _| Action.update({ count: 1000, content: Long }) }),
					Elem.button({ caption: "Long 10,000", label: "Show 10,000 long messages", on_press: |_, _| Action.update({ count: 10000, content: Long }) }),
					Elem.button({ caption: "Rich 100", label: "Show 100 metadata-rich messages", on_press: |_, _| Action.update({ count: 100, content: MetadataRich }) }),
					Elem.button({ caption: "Rich 1,000", label: "Show 1,000 metadata-rich messages", on_press: |_, _| Action.update({ count: 1000, content: MetadataRich }) }),
					Elem.button({ caption: "Rich 10,000", label: "Show 10,000 metadata-rich messages", on_press: |_, _| Action.update({ count: 10000, content: MetadataRich }) }),
				],
			),
			Elem.col({}, $messages),
		],
	)
}

main : Program(State)
main = Program.run({ setup: || { state: { count: 0, content: Short }, render } })
