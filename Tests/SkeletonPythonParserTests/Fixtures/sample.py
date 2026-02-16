from typing import Optional, List


class Animal:
    name: str
    age: int

    def __init__(self, name: str, age: int) -> None:
        self.name = name
        self.age = age

    def greet(self, greeting: str) -> str:
        return f"{greeting}, {self.name}"

    def describe(self) -> str:
        return f"{self.name} ({self.age})"


class Dog(Animal):
    breed: str

    def __init__(self, name: str, age: int, breed: str) -> None:
        super().__init__(name, age)
        self.breed = breed

    def fetch(self, item: str) -> bool:
        return True


class Shape:
    def area(self) -> float:
        return 0.0

    def perimeter(self) -> float:
        return 0.0
