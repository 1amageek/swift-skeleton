package com.example;

public interface Printable {
    void print();
    String format(String template);
}

public class Animal implements Printable {
    private String name;
    private int age;

    public Animal(String name, int age) {
        this.name = name;
        this.age = age;
    }

    public void print() {
        System.out.println(name);
    }

    public String format(String template) {
        return String.format(template, name);
    }

    public String getName() {
        return name;
    }
}

public class Dog extends Animal {
    private String breed;

    public Dog(String name, int age, String breed) {
        super(name, age);
        this.breed = breed;
    }

    public boolean fetch(String item) {
        return true;
    }
}

public enum Color {
    RED, GREEN, BLUE
}
