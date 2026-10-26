package main

import rl "github.com/gen2brain/raylib-go/raylib"

func main() {
	rl.SetConfigFlags(rl.FlagVsyncHint)
	rl.InitWindow(800, 450, "Go + raylib")
	defer rl.CloseWindow()

	for !rl.WindowShouldClose() {
		rl.BeginDrawing()
		rl.ClearBackground(rl.RayWhite)
		rl.DrawText("Go + raylib works!", 270, 100, 24, rl.DarkGray)
		rl.DrawCircle(400, 225, 50, rl.SkyBlue)
		rl.DrawText("Press Escape to close", 280, 340, 20, rl.Gray)
		rl.EndDrawing()
	}
}
