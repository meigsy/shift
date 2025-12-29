#!/usr/bin/env python3
"""Minimal test to verify /user/reset endpoint structure without dependencies."""

import ast
import sys

def check_endpoint_definition():
    """Parse the main.py file and check endpoint definition."""
    with open('main.py', 'r') as f:
        source = f.read()
    
    tree = ast.parse(source)
    
    # Find the reset_user_data function
    reset_func = None
    for node in ast.walk(tree):
        if isinstance(node, ast.FunctionDef) and node.name == 'reset_user_data':
            reset_func = node
            break
    
    if not reset_func:
        print("❌ reset_user_data function not found")
        return False
    
    # Check function parameters
    params = [arg.arg for arg in reset_func.args.args]
    print(f"Function parameters: {params}")
    
    # Check for ResetUserDataRequest
    for node in ast.walk(reset_func):
        if isinstance(node, ast.Name) and node.id == 'ResetUserDataRequest':
            print("✅ ResetUserDataRequest found in function")
            break
    else:
        print("❌ ResetUserDataRequest not found in function")
        return False
    
    # Check for @app.post decorator
    for node in ast.walk(tree):
        if isinstance(node, ast.FunctionDef) and node.name == 'reset_user_data':
            for decorator in node.decorator_list:
                if isinstance(decorator, ast.Attribute):
                    if (isinstance(decorator.value, ast.Name) and 
                        decorator.value.id == 'app' and
                        decorator.attr == 'post'):
                        # Check the route path
                        if len(decorator.args) > 0:
                            if isinstance(decorator.args[0], ast.Constant):
                                route = decorator.args[0].value
                                if '/user/reset' in route:
                                    print(f"✅ Found @app.post('{route}') decorator")
                                    return True
    
    print("❌ Could not verify @app.post('/user/reset') decorator")
    return False

if __name__ == "__main__":
    success = check_endpoint_definition()
    sys.exit(0 if success else 1)

