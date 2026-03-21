#!/usr/bin/env python3
"""
Migration script to extract functions from commands.zig to new module structure.
"""

import re
import sys
from pathlib import Path

def extract_function(content: str, func_name: str) -> tuple[str, int]:
    """
    Extract a function and its dependencies from the content.
    Returns (function_body, end_line_number)
    """
    # Find function start
    pattern = rf'^fn {func_name}\('
    match = re.search(pattern, content, re.MULTILINE)
    if not match:
        return None, 0
    
    start_pos = match.start()
    
    # Find function end by counting braces
    brace_count = 0
    in_string = False
    string_char = None
    i = start_pos
    
    while i < len(content):
        char = content[i]
        
        # Handle strings
        if not in_string and char in '"\'':
            in_string = True
            string_char = char
        elif in_string and char == string_char:
            # Check for escape
            if i > 0 and content[i-1] != '\\':
                in_string = False
                string_char = None
        
        # Handle braces (only when not in string)
        if not in_string:
            if char == '{':
                brace_count += 1
            elif char == '}':
                brace_count -= 1
                if brace_count == 0:
                    # Function complete
                    i += 1
                    break
        
        i += 1
    
    return content[start_pos:i], content[:i].count('\n')


def find_dependencies(content: str, func_body: str) -> list[str]:
    """Find types and functions that the function depends on."""
    deps = set()
    
    # Find type references (CamelCase)
    type_pattern = r'\b([A-Z][a-zA-Z0-9_]+)\b'
    for match in re.finditer(type_pattern, func_body):
        type_name = match.group(1)
        if type_name not in ['Self', 'Allocator', 'ArrayList', 'Error']:
            deps.add(type_name)
    
    # Find function calls (snake_case followed by '(')
    func_pattern = r'\b([a-z][a-z0-9_]+)\s*\('
    for match in re.finditer(func_pattern, func_body):
        func_name = match.group(1)
        if func_name not in ['if', 'while', 'for', 'switch', 'try', 'catch', 'errdefer', 'defer', 'return', 'break', 'continue']:
            deps.add(func_name)
    
    return sorted(deps)


def main():
    if len(sys.argv) < 3:
        print("Usage: python migrate_commands.py <function_name> <output_file>")
        sys.exit(1)
    
    func_name = sys.argv[1]
    output_file = sys.argv[2]
    
    commands_path = Path('/Users/davirian/dev/zig/sui-zig-rpc-client/src/commands.zig')
    content = commands_path.read_text()
    
    print(f"Extracting function: {func_name}")
    
    func_body, end_line = extract_function(content, func_name)
    if not func_body:
        print(f"Function {func_name} not found!")
        sys.exit(1)
    
    print(f"Function found, ends at line {end_line}")
    
    deps = find_dependencies(content, func_body)
    print(f"Dependencies: {', '.join(deps)}")
    
    # Write output
    output = f"""/// Auto-extracted from commands.zig
const std = @import("std");
const cli = @import("../cli.zig");
const client = @import("sui_client_zig");

// TODO: Add missing dependencies
// Dependencies found: {', '.join(deps)}

{func_body}
"""
    
    Path(output_file).write_text(output)
    print(f"Written to: {output_file}")


if __name__ == '__main__':
    main()
