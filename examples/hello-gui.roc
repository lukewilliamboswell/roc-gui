app "hello-gui"
    packages {pf: "../platform/main.roc"}
    imports [pf.Game.{ Bounds, Elem, Event }]
    provides [program] { Model } to pf

program = { init, update, render }

Model : { text : Str }

init : Bounds -> Model
init = \_ ->
    { text: "Hello, World!" } 

update : Model, Event -> Model
update = \model, event -> 
    when event is 
        Resize _ -> {model & text: "Resized"}
        KeyDown _ -> {model & text: "KeyDown"}
        KeyUp _ -> {model & text: "KeyUp"}
        Tick _ -> model

render : Model -> List Elem
render = \model ->
    [Text { text: model.text, top: 0, left: 0, size: 40, color: { r: 1, g: 1, b: 1, a: 1 } }]

