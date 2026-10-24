class_name Interactable
extends Node3D

@export var new_pos_node: Node3D


func interact(_by: Node) -> void:
	if _by is Player:
		print("INTERACTED")
		_by.position = new_pos_node.global_position
	else:
		print("INTERACT FAILED")
