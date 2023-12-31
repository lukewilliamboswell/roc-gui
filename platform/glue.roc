platform "gui"
    requires {} {notUsed : GlueStuff}
    exposes []
    packages {}
    imports [Game]
    provides [mainForHost]

# We are generating only glue for the types we need as a workaround
GlueStuff : [
    A Game.Bounds, 
    B Game.Elem, 
    C Game.Event
]

mainForHost : GlueStuff
mainForHost = notUsed
