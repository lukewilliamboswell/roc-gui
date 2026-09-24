app [State, main] { pf: platform "../../platform/main.roc" }

import pf.Gui

Content : [Short, Long, MetadataRich]

State : { count : U64, content : Content }

body : Content -> Str
body = |content| match content {
	Short => "Ready"
	Long => "A realistic notification body can contain enough detail to wrap over several lines, including context about the operation, its outcome, and the next action available to the reader."
	MetadataRich => "Ready"
}

render_message : U64, Content -> Gui.Elem(State)
render_message = |id, content| {
	primary = [Gui.text("Message ${id.to_str()}"), Gui.text("Body: ${body(content)}")]
	metadata = match content {
		MetadataRich => [Gui.text("Author: Operator"), Gui.text("Status: Delivered"), Gui.text("Received: just now")]
		_ => []
	}
	Gui.col({}, primary.concat(metadata))
}

render : State -> Gui.Elem(State)
render = |state| {
	var $messages = []
	for _ in List.repeat({}, state.count) {
		id = $messages.len() + 1
		$messages = $messages.append(render_message(id, state.content))
	}
	Gui.col(
		{},
		[
			Gui.row(
				{},
				[
					Gui.button({ caption: "Short 100", label: "Show 100 short messages", on_press: |_, _| Gui.update({ count: 100, content: Short }) }),
					Gui.button({ caption: "Short 1,000", label: "Show 1,000 short messages", on_press: |_, _| Gui.update({ count: 1000, content: Short }) }),
					Gui.button({ caption: "Short 10,000", label: "Show 10,000 short messages", on_press: |_, _| Gui.update({ count: 10000, content: Short }) }),
					Gui.button({ caption: "Long 100", label: "Show 100 long messages", on_press: |_, _| Gui.update({ count: 100, content: Long }) }),
					Gui.button({ caption: "Long 1,000", label: "Show 1,000 long messages", on_press: |_, _| Gui.update({ count: 1000, content: Long }) }),
					Gui.button({ caption: "Long 10,000", label: "Show 10,000 long messages", on_press: |_, _| Gui.update({ count: 10000, content: Long }) }),
					Gui.button({ caption: "Rich 100", label: "Show 100 metadata-rich messages", on_press: |_, _| Gui.update({ count: 100, content: MetadataRich }) }),
					Gui.button({ caption: "Rich 1,000", label: "Show 1,000 metadata-rich messages", on_press: |_, _| Gui.update({ count: 1000, content: MetadataRich }) }),
					Gui.button({ caption: "Rich 10,000", label: "Show 10,000 metadata-rich messages", on_press: |_, _| Gui.update({ count: 10000, content: MetadataRich }) }),
				],
			),
			Gui.col({}, $messages),
		],
	)
}

main : Gui.Program(State)
main = Gui.run({ init: |_access| { count: 0, content: Short }, render })
