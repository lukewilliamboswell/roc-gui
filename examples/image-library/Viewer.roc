import pf.Elem
import Gallery
import Theme

Viewer := [].{
	Transform : { fit : Elem.ImageFit, grayscale : Bool }
	initial : Transform
	initial = { fit: Contain, grayscale: False }
	render_image : Gallery.Asset, Transform -> Elem.Elem(a)
	render_image = |asset, transform| Elem.image(Elem.ImageProps.{ label: "Selected image", bytes: asset.bytes, format: asset.format, fit: transform.fit, grayscale: transform.grayscale, width: Fill, height: Fill, grow: True, radius: Theme.media_radius })
	fit_label : Elem.ImageFit -> Str
	fit_label = |fit| match fit { Contain => "Fit", Cover => "Crop to fill", Fill => "Stretch", None => "Actual size", ScaleDown => "Scale down" }
}
