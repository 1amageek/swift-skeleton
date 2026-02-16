interface Printable {
    name: string;
    print(): void;
}

interface Serializable {
    serialize(): string;
}

class Animal implements Printable {
    name: string;
    age: number;

    constructor(name: string, age: number) {
        this.name = name;
        this.age = age;
    }

    print(): void {
        console.log(this.name);
    }

    greet(greeting: string): string {
        return `${greeting}, ${this.name}`;
    }
}

class Dog extends Animal implements Serializable {
    breed: string;

    constructor(name: string, age: number, breed: string) {
        super(name, age);
        this.breed = breed;
    }

    serialize(): string {
        return JSON.stringify(this);
    }

    fetch(item: string): boolean {
        return true;
    }
}

enum Direction {
    Up = "UP",
    Down = "DOWN",
    Left = "LEFT",
    Right = "RIGHT",
}

type Point = {
    x: number;
    y: number;
};
