use crate::{
    AnyElement, AnyEntity, AnyWeakEntity, App, Bounds, ContentMask, Context, Element, ElementId,
    Entity, EntityId, GlobalElementId, InspectorElementId, IntoElement, LayoutId, PaintIndex,
    Pixels, PrepaintStateIndex, Render, Style, StyleRefinement, TextStyle, WeakEntity,
};
use crate::{Empty, Window};
use anyhow::Result;
use collections::FxHashSet;
use refineable::Refineable;
use std::mem;
use std::rc::Rc;
use std::{any::TypeId, fmt, ops::Range};

pub(crate) struct AnyViewState {
    pub(crate) prepaint_range: Range<PrepaintStateIndex>,
    pub(crate) paint_range: Range<PaintIndex>,
    cache_key: ViewCacheKey,
    accessed_entities: FxHashSet<EntityId>,
    refresh_descendants: bool,
    independent_children: bool,
}

#[derive(Default)]
struct ViewCacheKey {
    bounds: Bounds<Pixels>,
    content_mask: ContentMask<Pixels>,
    text_style: TextStyle,
}

impl<V: Render> Element for Entity<V> {
    type RequestLayoutState = AnyElement;
    type PrepaintState = ();

    fn id(&self) -> Option<ElementId> {
        Some(ElementId::View(self.entity_id()))
    }

    fn source_location(&self) -> Option<&'static std::panic::Location<'static>> {
        None
    }

    fn request_layout(
        &mut self,
        _id: Option<&GlobalElementId>,
        _inspector_id: Option<&InspectorElementId>,
        window: &mut Window,
        cx: &mut App,
    ) -> (LayoutId, Self::RequestLayoutState) {
        let mut element = self.update(cx, |view, cx| view.render(window, cx).into_any_element());
        let layout_id = window.with_rendered_view(self.entity_id(), |window| {
            element.request_layout(window, cx)
        });
        (layout_id, element)
    }

    fn prepaint(
        &mut self,
        _id: Option<&GlobalElementId>,
        _inspector_id: Option<&InspectorElementId>,
        _: Bounds<Pixels>,
        element: &mut Self::RequestLayoutState,
        window: &mut Window,
        cx: &mut App,
    ) {
        window.set_view_id(self.entity_id());
        window.with_rendered_view(self.entity_id(), |window| element.prepaint(window, cx));
    }

    fn paint(
        &mut self,
        _id: Option<&GlobalElementId>,
        _inspector_id: Option<&InspectorElementId>,
        _: Bounds<Pixels>,
        element: &mut Self::RequestLayoutState,
        _: &mut Self::PrepaintState,
        window: &mut Window,
        cx: &mut App,
    ) {
        window.with_rendered_view(self.entity_id(), |window| element.paint(window, cx));
    }
}

/// A dynamically-typed handle to a view, which can be downcast to a [Entity] for a specific type.
#[derive(Clone, Debug)]
pub struct AnyView {
    entity: AnyEntity,
    render: fn(&AnyView, &mut Window, &mut App) -> AnyElement,
    cached_style: Option<Rc<StyleRefinement>>,
    independent_children: bool,
}

impl<V: Render> From<Entity<V>> for AnyView {
    fn from(value: Entity<V>) -> Self {
        AnyView {
            entity: value.into_any(),
            render: any_view::render::<V>,
            cached_style: None,
            independent_children: false,
        }
    }
}

impl AnyView {
    /// Indicate that this view should be cached when using it as an element.
    /// When using this method, the view's previous layout and paint will be recycled from the previous frame if [Context::notify] has not been called since it was rendered.
    /// The one exception is when [Window::refresh] is called, in which case caching is ignored.
    pub fn cached(mut self, style: StyleRefinement) -> Self {
        self.cached_style = Some(style.into());
        self.independent_children = false;
        self
    }

    /// Cache a view whose descendants independently invalidate their own content.
    ///
    /// An ordinary dirty rebuild with unchanged bounds, clip, and text style can
    /// reuse clean child views. The caller must notify every affected descendant
    /// when changing other inherited paint or interaction context (for example
    /// group-hover state). Use `cached` unless that contract is guaranteed.
    /// Geometry, clip, text style, and explicit window refresh still refresh children.
    pub fn cached_with_independent_children(mut self, style: StyleRefinement) -> Self {
        self.cached_style = Some(style.into());
        self.independent_children = true;
        self
    }

    /// Convert this to a weak handle.
    pub fn downgrade(&self) -> AnyWeakView {
        AnyWeakView {
            entity: self.entity.downgrade(),
            render: self.render,
        }
    }

    /// Convert this to a [Entity] of a specific type.
    /// If this handle does not contain a view of the specified type, returns itself in an `Err` variant.
    pub fn downcast<T: 'static>(self) -> Result<Entity<T>, Self> {
        match self.entity.downcast() {
            Ok(entity) => Ok(entity),
            Err(entity) => Err(Self {
                entity,
                render: self.render,
                cached_style: self.cached_style,
                independent_children: self.independent_children,
            }),
        }
    }

    /// Gets the [TypeId] of the underlying view.
    pub fn entity_type(&self) -> TypeId {
        self.entity.entity_type
    }

    /// Gets the entity id of this handle.
    pub fn entity_id(&self) -> EntityId {
        self.entity.entity_id()
    }
}

impl PartialEq for AnyView {
    fn eq(&self, other: &Self) -> bool {
        self.entity == other.entity
    }
}

impl Eq for AnyView {}

impl Element for AnyView {
    type RequestLayoutState = Option<AnyElement>;
    type PrepaintState = Option<AnyElement>;

    fn id(&self) -> Option<ElementId> {
        Some(ElementId::View(self.entity_id()))
    }

    fn source_location(&self) -> Option<&'static core::panic::Location<'static>> {
        None
    }

    fn request_layout(
        &mut self,
        _id: Option<&GlobalElementId>,
        _inspector_id: Option<&InspectorElementId>,
        window: &mut Window,
        cx: &mut App,
    ) -> (LayoutId, Self::RequestLayoutState) {
        window.with_rendered_view(self.entity_id(), |window| {
            // Disable caching when inspecting so that mouse_hit_test has all hitboxes.
            let caching_disabled = window.is_inspector_picking(cx);
            match self.cached_style.as_ref() {
                Some(style) if !caching_disabled => {
                    let mut root_style = Style::default();
                    root_style.refine(style);
                    let layout_id = window.request_layout(root_style, None, cx);
                    (layout_id, None)
                }
                _ => {
                    let mut element = (self.render)(self, window, cx);
                    let layout_id = element.request_layout(window, cx);
                    (layout_id, Some(element))
                }
            }
        })
    }

    fn prepaint(
        &mut self,
        global_id: Option<&GlobalElementId>,
        _inspector_id: Option<&InspectorElementId>,
        bounds: Bounds<Pixels>,
        element: &mut Self::RequestLayoutState,
        window: &mut Window,
        cx: &mut App,
    ) -> Option<AnyElement> {
        window.set_view_id(self.entity_id());
        window.with_rendered_view(self.entity_id(), |window| {
            if let Some(mut element) = element.take() {
                element.prepaint(window, cx);
                return Some(element);
            }

            window.with_element_state::<AnyViewState, _>(
                global_id.unwrap(),
                |element_state, window| {
                    let content_mask = window.content_mask();
                    let text_style = window.text_style();

                    // A dirty view with unchanged inherited geometry/style only needs
                    // to rebuild itself. Its children retain their own dirty checks.
                    // Cold/layout/style/global refreshes still invalidate descendants.
                    let refresh_descendants = !self.independent_children
                        || window.refreshing
                        || element_state.as_ref().is_none_or(|state| {
                            state.independent_children != self.independent_children
                                || state.cache_key.bounds != bounds
                                || state.cache_key.content_mask != content_mask
                                || state.cache_key.text_style != text_style
                        });

                    if let Some(mut element_state) = element_state
                        && element_state.cache_key.bounds == bounds
                        && element_state.cache_key.content_mask == content_mask
                        && element_state.cache_key.text_style == text_style
                        && !window.dirty_views.contains(&self.entity_id())
                        && !window.refreshing
                        && element_state.independent_children == self.independent_children
                    {
                        let prepaint_start = window.prepaint_index();
                        window.reuse_prepaint(element_state.prepaint_range.clone());
                        cx.entities
                            .extend_accessed(&element_state.accessed_entities);
                        let prepaint_end = window.prepaint_index();
                        element_state.prepaint_range = prepaint_start..prepaint_end;

                        return (None, element_state);
                    }

                    let refreshing = mem::replace(&mut window.refreshing, refresh_descendants);
                    let prepaint_start = window.prepaint_index();
                    let (mut element, accessed_entities) = cx.detect_accessed_entities(|cx| {
                        let mut element = (self.render)(self, window, cx);
                        element.layout_as_root(bounds.size.into(), window, cx);
                        element.prepaint_at(bounds.origin, window, cx);
                        element
                    });

                    let prepaint_end = window.prepaint_index();
                    window.refreshing = refreshing;

                    (
                        Some(element),
                        AnyViewState {
                            accessed_entities,
                            refresh_descendants,
                            independent_children: self.independent_children,
                            prepaint_range: prepaint_start..prepaint_end,
                            paint_range: PaintIndex::default()..PaintIndex::default(),
                            cache_key: ViewCacheKey {
                                bounds,
                                content_mask,
                                text_style,
                            },
                        },
                    )
                },
            )
        })
    }

    fn paint(
        &mut self,
        global_id: Option<&GlobalElementId>,
        _inspector_id: Option<&InspectorElementId>,
        _bounds: Bounds<Pixels>,
        _: &mut Self::RequestLayoutState,
        element: &mut Self::PrepaintState,
        window: &mut Window,
        cx: &mut App,
    ) {
        window.with_rendered_view(self.entity_id(), |window| {
            let caching_disabled = window.is_inspector_picking(cx);
            if self.cached_style.is_some() && !caching_disabled {
                window.with_element_state::<AnyViewState, _>(
                    global_id.unwrap(),
                    |element_state, window| {
                        let mut element_state = element_state.unwrap();

                        let paint_start = window.paint_index();

                        if let Some(element) = element {
                            let refresh_descendants =
                                window.refreshing || element_state.refresh_descendants;
                            let refreshing =
                                mem::replace(&mut window.refreshing, refresh_descendants);
                            element.paint(window, cx);
                            window.refreshing = refreshing;
                        } else {
                            window.reuse_paint(element_state.paint_range.clone());
                        }

                        let paint_end = window.paint_index();
                        element_state.paint_range = paint_start..paint_end;

                        ((), element_state)
                    },
                )
            } else {
                element.as_mut().unwrap().paint(window, cx);
            }
        });
    }
}

impl<V: 'static + Render> IntoElement for Entity<V> {
    type Element = Entity<V>;

    fn into_element(self) -> Self::Element {
        self
    }
}

impl IntoElement for AnyView {
    type Element = Self;

    fn into_element(self) -> Self::Element {
        self
    }
}

/// A weak, dynamically-typed view handle that does not prevent the view from being released.
pub struct AnyWeakView {
    entity: AnyWeakEntity,
    render: fn(&AnyView, &mut Window, &mut App) -> AnyElement,
}

impl AnyWeakView {
    /// Convert to a strongly-typed handle if the referenced view has not yet been released.
    pub fn upgrade(&self) -> Option<AnyView> {
        let entity = self.entity.upgrade()?;
        Some(AnyView {
            entity,
            render: self.render,
            cached_style: None,
            independent_children: false,
        })
    }
}

impl<V: 'static + Render> From<WeakEntity<V>> for AnyWeakView {
    fn from(view: WeakEntity<V>) -> Self {
        AnyWeakView {
            entity: view.into(),
            render: any_view::render::<V>,
        }
    }
}

impl PartialEq for AnyWeakView {
    fn eq(&self, other: &Self) -> bool {
        self.entity == other.entity
    }
}

impl std::fmt::Debug for AnyWeakView {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("AnyWeakView")
            .field("entity_id", &self.entity.entity_id)
            .finish_non_exhaustive()
    }
}

mod any_view {
    use crate::{AnyElement, AnyView, App, IntoElement, Render, Window};

    pub(crate) fn render<V: 'static + Render>(
        view: &AnyView,
        window: &mut Window,
        cx: &mut App,
    ) -> AnyElement {
        let view = view.clone().downcast::<V>().unwrap();
        view.update(cx, |view, cx| view.render(window, cx).into_any_element())
    }
}

/// A view that renders nothing
pub struct EmptyView;

impl Render for EmptyView {
    fn render(&mut self, _window: &mut Window, _cx: &mut Context<Self>) -> impl IntoElement {
        Empty
    }
}

#[cfg(test)]
mod cache_tests {
    use super::*;
    use crate::prelude::*;
    use crate::{AppContext, ParentElement, Styled, TestAppContext, div, px};
    use std::cell::Cell;

    struct Leaf(Rc<Cell<u64>>, Rc<Cell<u64>>);
    impl Render for Leaf {
        fn render(&mut self, _: &mut Window, _: &mut Context<Self>) -> impl IntoElement {
            self.0.set(self.0.get() + 1);
            let hovered = self.1.clone();
            div()
                .id("leaf")
                .w(px(20.0))
                .h(px(20.0))
                .bg(crate::rgb(0x123456))
                .on_hover(move |entered, _, _| {
                    if *entered {
                        hovered.set(hovered.get() + 1);
                    }
                })
        }
    }
    struct Parent {
        children: Vec<Entity<Leaf>>,
        renders: Rc<Cell<u64>>,
        color: u32,
    }
    fn cached(view: AnyView, width: f32) -> AnyView {
        let mut layout = div().w(px(width)).h(px(20.0));
        view.cached_with_independent_children(layout.style().clone())
    }
    impl Render for Parent {
        fn render(&mut self, _: &mut Window, _: &mut Context<Self>) -> impl IntoElement {
            self.renders.set(self.renders.get() + 1);
            div().flex().text_color(crate::rgb(self.color)).children(
                self.children
                    .iter()
                    .cloned()
                    .map(|child| cached(child.into(), 20.0)),
            )
        }
    }
    struct Root {
        parent: Entity<Parent>,
        width: f32,
        independent: bool,
        clip_width: f32,
        prefix: usize,
        abort_replay: bool,
    }
    impl Render for Root {
        fn render(&mut self, _: &mut Window, _: &mut Context<Self>) -> impl IntoElement {
            let view = AnyView::from(self.parent.clone());
            let mut layout = div().w(px(self.width)).h(px(20.0));
            let child = if self.independent {
                view.cached_with_independent_children(layout.style().clone())
            } else {
                view.cached(layout.style().clone())
            };
            let abort_replay = self.abort_replay;
            let parent_id = self.parent.entity_id();
            div()
                .w(px(self.clip_width))
                .h(px(20.0))
                .overflow_hidden()
                .children((0..self.prefix).map(|i| {
                    div()
                        .id(i)
                        .absolute()
                        .w(px(1.0))
                        .h(px(1.0))
                        .bg(crate::rgb(0x654321))
                        .on_hover(|_, _, _| {})
                }))
                .child(
                    crate::canvas(
                        move |_, window, _| {
                            if abort_replay {
                                let range = window
                                    .rendered_frame
                                    .element_states
                                    .iter()
                                    .find_map(|(key, boxed)| {
                                        (key.0.0.last() == Some(&ElementId::View(parent_id)))
                                            .then(|| {
                                                boxed
                                                    .inner
                                                    .downcast_ref::<Option<AnyViewState>>()
                                                    .and_then(Option::as_ref)
                                                    .map(|state| state.prepaint_range.clone())
                                            })
                                            .flatten()
                                    })
                                    .expect("cached parent state");
                                assert!(
                                    window
                                        .transact(|window| {
                                            window.reuse_prepaint(range);
                                            Err::<(), ()>(())
                                        })
                                        .is_err()
                                );
                            }
                        },
                        |_, _, _, _| {},
                    )
                    .absolute()
                    .w(px(0.0))
                    .h(px(0.0)),
                )
                .child(child)
        }
    }

    #[crate::test]
    fn dirty_cached_parent_preserves_clean_children_but_geometry_and_refresh_rebuild(
        cx: &mut TestAppContext,
    ) {
        let a = Rc::new(Cell::new(0));
        let b = Rc::new(Cell::new(0));
        let parent_count = Rc::new(Cell::new(0));
        let hovered_a = Rc::new(Cell::new(0));
        let hovered_b = Rc::new(Cell::new(0));
        let (root, cx) = cx.add_window_view(|_, cx| {
            let first = cx.new(|_| Leaf(a.clone(), hovered_a.clone()));
            let second = cx.new(|_| Leaf(b.clone(), hovered_b.clone()));
            let parent = cx.new(|_| Parent {
                children: vec![first, second],
                renders: parent_count.clone(),
                color: 0,
            });
            Root {
                parent,
                width: 100.0,
                independent: true,
                clip_width: 200.0,
                prefix: 0,
                abort_replay: false,
            }
        });
        cx.run_until_parked();
        let parent = root.read_with(cx, |root, _| root.parent.clone());
        let first = parent.read_with(cx, |parent, _| parent.children[0].clone());
        let counts = || (a.get(), b.get(), parent_count.get());
        let before = counts();
        parent.update(cx, |_, cx| cx.notify());
        cx.run_until_parked();
        assert_eq!(counts(), (before.0, before.1, before.2 + 1));
        cx.update(|window, _| assert_eq!(window.rendered_frame.cached_view_replay_count(), 0));
        root.update(cx, |root, cx| {
            root.prefix = 3;
            root.abort_replay = true;
            cx.notify();
        });
        cx.run_until_parked();
        cx.update(|window, _| assert!(window.rendered_frame.cached_view_replay_count() > 0));
        let before = counts();
        parent.update(cx, |_, cx| cx.notify());
        cx.run_until_parked();
        assert_eq!(counts(), (before.0, before.1, before.2 + 1));
        // A descendant notification after parent reuse must still reach the ancestor.
        let before = counts();
        first.update(cx, |_, cx| cx.notify());
        cx.run_until_parked();
        assert_eq!(counts(), (before.0 + 1, before.1, before.2 + 1));
        cx.simulate_mouse_move(
            crate::point(px(5.0), px(5.0)),
            None,
            crate::Modifiers::none(),
        );
        cx.simulate_mouse_move(
            crate::point(px(25.0), px(5.0)),
            None,
            crate::Modifiers::none(),
        );
        assert_eq!((hovered_a.get(), hovered_b.get()), (1, 1));
        cx.update(|window, _| assert_eq!(window.rendered_frame.scene.quads.len(), 5));
        root.update(cx, |root, cx| {
            root.prefix = 0;
            root.abort_replay = false;
            cx.notify();
        });
        cx.run_until_parked();
        parent.update(cx, |_, cx| cx.notify());
        cx.run_until_parked();
        cx.simulate_mouse_move(
            crate::point(px(5.0), px(5.0)),
            None,
            crate::Modifiers::none(),
        );
        assert_eq!((hovered_a.get(), hovered_b.get()), (2, 1));
        cx.update(|window, _| assert_eq!(window.rendered_frame.scene.quads.len(), 2));
        let before = counts();
        root.update(cx, |root, cx| {
            root.width = 120.0;
            cx.notify();
        });
        cx.run_until_parked();
        assert_eq!(counts(), (before.0 + 1, before.1 + 1, before.2 + 1));
        let before = counts();
        cx.update(|window, _| window.refresh());
        cx.run_until_parked();
        assert_eq!(counts(), (before.0 + 1, before.1 + 1, before.2 + 1));
        let before = counts();
        parent.update(cx, |parent, cx| {
            parent.color = 0xabcdef;
            cx.notify();
        });
        cx.run_until_parked();
        assert_eq!(counts(), (before.0 + 1, before.1 + 1, before.2 + 1));
        let before = counts();
        root.update(cx, |root, cx| {
            root.clip_width = 50.0;
            cx.notify();
        });
        cx.run_until_parked();
        assert_eq!(counts(), (before.0 + 1, before.1 + 1, before.2 + 1));
        // Policy changes invalidate existing caches, and default caching remains conservative.
        let before = counts();
        root.update(cx, |root, cx| {
            root.independent = false;
            cx.notify();
        });
        cx.run_until_parked();
        assert_eq!(counts(), (before.0 + 1, before.1 + 1, before.2 + 1));
        let before = counts();
        parent.update(cx, |_, cx| cx.notify());
        cx.run_until_parked();
        assert_eq!(counts(), (before.0 + 1, before.1 + 1, before.2 + 1));
        root.update(cx, |root, cx| {
            root.independent = true;
            cx.notify();
        });
        cx.run_until_parked();
        // Removing a cached child must retire its replay range; the survivor moves.
        let before = counts();
        parent.update(cx, |parent, cx| {
            parent.children.remove(0);
            cx.notify();
        });
        cx.run_until_parked();
        assert_eq!(counts(), (before.0, before.1 + 1, before.2 + 1));
    }
}
