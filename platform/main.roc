platform "gui"
    requires {Model} { program : _ }
    exposes [Game]
    packages {}
    imports [Game.{ Bounds, Elem, Event }]
    provides [mainForHost]

# TODO add when not giving UNUSED DEFINITION warning  
# Program : {
#     init : Bounds -> Model,
#     update : Model, Event -> Model,
#     render : Model -> List Elem,
# }

init : Bounds -> Box Model
init =  \bounds -> Box.box (program.init bounds)

update : Box Model, Event -> Box Model
update = \boxedModel, event -> Box.box (program.update (Box.unbox boxedModel) event)

render : Box Model -> List Elem
render = \boxedModel -> program.render (Box.unbox boxedModel)

ProgramForHost : {
    init : Bounds -> Box Model,
    update : Box Model, Event -> Box Model,
    render : Box Model -> List Elem,
}

mainForHost : ProgramForHost
mainForHost = {init,update,render}
