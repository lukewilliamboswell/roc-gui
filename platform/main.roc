platform "gui"
    requires {} { program : _ }
    exposes [Game]
    packages {}
    imports [Game.{ Bounds, Elem, Event }]
    provides [mainForHost]

ForHost : {
    init : InitForHost,
    update : UpdateForHost,
    render : RenderForHost,
}

InitForHost : Bounds -> List U8
UpdateForHost : List U8, Event -> List U8
RenderForHost : List U8 -> List Elem

# TODO allow changing the window title - maybe via a Task, since that shouldn't happen all the time
mainForHost : ForHost
mainForHost = program
