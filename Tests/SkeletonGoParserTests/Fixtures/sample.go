package sample

type Stringer interface {
	String() string
}

type Animal struct {
	Name string
	Age  int
}

func (a *Animal) String() string {
	return a.Name
}

func (a *Animal) Greet(greeting string) string {
	return greeting + " " + a.Name
}

type Dog struct {
	Animal
	Breed string
}

func (d *Dog) Fetch(item string) bool {
	return true
}

func NewAnimal(name string, age int) *Animal {
	return &Animal{Name: name, Age: age}
}
