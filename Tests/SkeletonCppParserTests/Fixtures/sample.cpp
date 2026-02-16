class Animal {
public:
    std::string name;
    int age;

    Animal(std::string name, int age) : name(name), age(age) {}

    virtual void print() {
        std::cout << name << std::endl;
    }

    std::string greet(std::string greeting) {
        return greeting + " " + name;
    }
};

class Dog : public Animal {
public:
    std::string breed;

    Dog(std::string name, int age, std::string breed)
        : Animal(name, age), breed(breed) {}

    bool fetch(std::string item) {
        return true;
    }
};

struct Point {
    double x;
    double y;

    double distance(Point other) {
        return 0.0;
    }
};

enum Color {
    Red,
    Green,
    Blue,
};

union Value {
    int intVal;
    float floatVal;
    char charVal;
};

class Outer {
public:
    int x;

    class Inner {
    public:
        int y;
    };
};
