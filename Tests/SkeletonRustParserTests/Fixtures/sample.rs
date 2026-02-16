pub trait Drawable {
    fn draw(&self);
    fn area(&self) -> f64;
}

pub struct Circle {
    pub radius: f64,
    pub center_x: f64,
    pub center_y: f64,
}

impl Circle {
    pub fn new(radius: f64) -> Circle {
        Circle {
            radius,
            center_x: 0.0,
            center_y: 0.0,
        }
    }

    pub fn circumference(&self) -> f64 {
        2.0 * std::f64::consts::PI * self.radius
    }
}

impl Drawable for Circle {
    fn draw(&self) {
        println!("Drawing circle");
    }

    fn area(&self) -> f64 {
        std::f64::consts::PI * self.radius * self.radius
    }
}

pub enum Shape {
    Circle(Circle),
    Rectangle { width: f64, height: f64 },
}

impl Shape {
    pub fn describe(&self) -> String {
        match self {
            Shape::Circle(_) => "circle".to_string(),
            Shape::Rectangle { .. } => "rectangle".to_string(),
        }
    }
}
