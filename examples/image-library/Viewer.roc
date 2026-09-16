import pf.Elem
import Gallery
import Theme

Viewer := [].{
	Transform : { fit : Elem.ImageFit, grayscale : Bool }
	initial : Transform
	initial = { fit: Contain, grayscale: False }
	render_image : Gallery.Asset, Transform -> Elem.Elem(a)
	render_image = |asset, transform| Elem.image(Elem.ImageProps.{ label: "Selected image", bytes: asset.bytes, format: asset.format, fit: transform.fit, grayscale: transform.grayscale, width: Fill, height: Px(0), min_height: Px(0), grow: True, radius: Theme.media_radius })
}
