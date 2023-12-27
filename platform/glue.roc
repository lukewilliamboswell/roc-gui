platform "gui"
    requires {} { program : _ }
    exposes []
    packages {}
    imports [Game.{ Bounds, Elem, Event }]
    provides [mainForHost]

Model : {}

ForHost : {
    init : Bounds -> Model,
    update : Model, Event -> Model,
    render : Model -> List Elem,
}

mainForHost : ForHost
mainForHost = program
