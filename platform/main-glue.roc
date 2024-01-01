platform "gui"
    requires {} { notUsed : _ }
    exposes []
    packages {}
    imports [Types.{ Bounds, Elem, Event }]
    provides [mainForHost]

# We are generating only glue for the types we need as a workaround until `roc glue`
# is able to generate correctly for the platform
GlueStuff : {
    a : List Bounds,
    b : List Event,
    c : List Elem,
}

mainForHost : GlueStuff
mainForHost = notUsed
