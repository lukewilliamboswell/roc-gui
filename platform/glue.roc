platform "gui"
    requires {} {notUsed : GlueStuff}
    exposes []
    packages {}
    imports [Game]
    provides [mainForHost]

GlueStuff : [
    A Game.Bounds, 
    B Game.Elem, 
    C Game.Event
]

mainForHost : GlueStuff
mainForHost = notUsed
