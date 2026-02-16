package com.example

interface Drawable {
    fun draw()
    fun resize(width: Int, height: Int): Boolean
}

open class Shape(val name: String) : Drawable {
    var area: Double = 0.0

    constructor(name: String, area: Double) : this(name) {
        this.area = area
    }

    override fun draw() {
        println("Drawing $name")
    }

    override fun resize(width: Int, height: Int): Boolean {
        return true
    }

    fun describe(): String {
        return "Shape: $name"
    }
}

class Circle(val radius: Double) : Shape("circle") {
    val circumference: Double = 2 * Math.PI * radius

    fun calculateArea(): Double {
        return Math.PI * radius * radius
    }
}

object Singleton {
    fun getInstance(): Singleton {
        return this
    }
}

enum class Color {
    RED, GREEN, BLUE
}
