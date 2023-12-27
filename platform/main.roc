platform "gui"
    requires {Model} { program : _ }
    exposes [Game]
    packages {}
    imports [Game.{ Bounds, Elem, Event }]
    provides [mainForHost]

ForHost : {
    init : Bounds -> Model,
    update : Model, Event -> Model,
    render : Model -> List Elem,
} 

mainForHost : ForHost
mainForHost = program
