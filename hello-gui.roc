app "hello-gui"
    packages { 
        pf: "platform/main.roc",
        json: "https://github.com/lukewilliamboswell/roc-json/releases/download/0.6.0/hJySbEhJV026DlVCHXGOZNOeoOl7468y9F9Buhj0J18.tar.br",
    }
    imports [
        pf.Game.{ Bounds, Elem, Event },
        json.Core.{json},
    ]
    provides [program] { Model } to pf

program = { init, update, render }

Model : { text : Str }

init : Bounds -> List U8
init = \_ -> 
    { text: "Hello, World!" } 
    |> Encode.toBytes json

update : List U8, Event -> List U8
update = \modelBytes, event ->
    when Decode.fromBytes modelBytes json is 
        Err _ -> crash "unreachable - unable to decode model"
        Ok model -> 
            when event is 
                Tick _ -> {model & text: "TICK"} |> Encode.toBytes json
                _ -> modelBytes
        

render : List U8 -> List Elem
render = \modelBytes -> 
    when Decode.fromBytes modelBytes json is 
        Err _ -> crash "unreachable - unable to decode model"
        Ok model -> 
            [Text { text: model.text, top: 0, left: 0, size: 40, color: { r: 1, g: 1, b: 1, a: 1 } }]


