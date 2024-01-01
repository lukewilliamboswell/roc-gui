platform "gui"
    requires {Model} { program : _ }
    exposes [Game]
    packages {}
    imports [Game.{ Bounds, Elem, Event }]
    provides [mainForHost]

# TODO add to annotation for program in header 
# when not giving UNUSED DEFINITION warning  
# 
# Program : {
#     init : Bounds -> Model,
#     update : Model, Event -> Model,
#     render : Model -> List Elem,
# }

# We box the model before passing to the Host and unbox when passed to Roc
ProgramForHost : {
    init : Bounds -> Box Model,
    update : Box Model, Event -> Box Model,
    render : Box Model -> {elems : List Elem, model : Box Model },
}

init : Bounds -> Box Model
init =  \bounds -> Box.box (program.init bounds)

update : Box Model, Event -> Box Model
update = \boxedModel, event -> Box.box (program.update (Box.unbox boxedModel) event)

render : Box Model -> {elems : List Elem, model : Box Model }
render = \boxedModel -> {elems: program.render (Box.unbox boxedModel), model: boxedModel}

mainForHost : ProgramForHost
mainForHost = {init,update,render}
