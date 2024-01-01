#![allow(unused)]

mod graphics;
mod gui;
mod roc;

#[no_mangle]
pub extern "C" fn rust_main() -> i32 {
    let bounds = roc_app::Bounds {
        width: 1900.0,
        height: 1000.0,
    };

    let mut roc_main = roc::main_for_host();

    roc_main.init(bounds);

    let tick = std::time::Duration::from_secs(1);
    let tick_event = roc_app::Event::Tick(u64::try_from(tick.as_millis()).unwrap()); 
       
    roc_main.update(tick_event);

    let elems = roc_main.render(); 

    // let elems = render_return.elems;
    
    // model = render_return.model;

    dbg!(elems);

    // TODO RE-INSTATE THE GUI PARTS
    // gui::run_event_loop("RocOut!", bounds).expect("Error running event loop");

    // Exit code
    0
}
