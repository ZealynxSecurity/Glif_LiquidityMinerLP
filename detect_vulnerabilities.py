import re
import os
import subprocess

# Función para buscar archivos Solidity en el directorio 'src' y subdirectorios
def find_solidity_files(base_dir):
    solidity_files = []
    src_dir = os.path.join(base_dir, 'src')
    for root, dirs, files in os.walk(src_dir):
        for file in files:
            if file.endswith('.sol'):
                solidity_files.append(os.path.join(root, file))
    return solidity_files

# Regex para detectar una división seguida de cualquier otra operación aritmética
vulnerability_patterns = {
    "division_not_at_end": re.compile(r'/.*[\+\-\*]', re.DOTALL)
}

# Función para analizar un archivo Solidity en busca de vulnerabilidades
def analyze_file(filepath):
    vulnerabilities = []
    with open(filepath, 'r') as file:
        code = file.readlines()  # Leer el archivo línea por línea
        inside_comment_block = False
        for line_number, line in enumerate(code):
            stripped_line = line.strip()
            if stripped_line.startswith("/*"):
                inside_comment_block = True
            if inside_comment_block:
                if stripped_line.endswith("*/"):
                    inside_comment_block = False
                continue  # Ignorar todo dentro de bloques de comentarios
            if stripped_line.startswith("//"):
                continue  # Ignorar comentarios de línea
            for name, pattern in vulnerability_patterns.items():
                if pattern.search(line):
                    vulnerabilities.append((name, line_number + 1, line.strip()))
    return vulnerabilities

# Función para crear y ejecutar una prueba de fuzzing con Foundry
def create_and_run_fuzz_test(vulnerabilities, test_dir, show_output_in_terminal):
    test_code_template = """
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test, console} from "forge-std/Test.sol";

contract VulnerabilityTest is Test {
    function testfuzzTestVulnerability(uint256 a, uint256 b) public {
        uint256 boundedA = bound(a, 1, type(uint128).max); 
        uint256 boundedB = bound(b, 1, type(uint128).max); 
        
        uint256 result = (boundedA / boundedB) * 10;

        uint256 expectedResult = (boundedA * 10) / boundedB;
        
        console.log("Bounded A", boundedA);
        console.log("Bounded B", boundedB);
        console.log("Result", result);
        console.log("Expected Result", expectedResult);

        if (result != expectedResult) {
            console.log("Assertion failed");
            console.log("Bounded A:", boundedA);
            console.log("Bounded B:", boundedB);
            console.log("Result:", result);
            console.log("Expected Result:", expectedResult);
        }
        
        assert(result == expectedResult); 
    }
}
"""
    test_file_path = os.path.join(test_dir, "VulnerabilityTest.t.sol")

    with open(test_file_path, 'w') as test_file:
        test_file.write(test_code_template)

    if show_output_in_terminal:
        # Ejecutar la prueba con Foundry y mostrar la salida en la terminal
        result = subprocess.run(["forge", "test", "--mc", "VulnerabilityTest", "--mt", "testfuzzTestVulnerability", "-vvvv"], text=True)
        print(result.stdout)
        return result.stdout
    else:
        # Ejecutar la prueba con Foundry y capturar la salida
        result = subprocess.run(["forge", "test", "--mc", "VulnerabilityTest", "--mt", "fuzzTestVulnerability", "-vvvv"], capture_output=True, text=True)
        return result.stdout

# Directorio base desde el cual se ejecuta el script
base_directory = os.getcwd()
test_directory = os.path.join(base_directory, 'test')

# Crear el directorio de pruebas si no existe
os.makedirs(test_directory, exist_ok=True)

# Preguntar al usuario si desea ejecutar las pruebas en la terminal
show_output_in_terminal = input("Do you want to run the tests in the terminal? (y/n): ").strip().lower() == 'y'

# Buscar todos los archivos Solidity en la carpeta 'src'
solidity_files = find_solidity_files(base_directory)

# Verificar que se encontraron archivos Solidity
if not solidity_files:
    print("No Solidity files found in the 'src' folder.")
    exit(1)

# Analizar cada archivo Solidity
report = {}
for solidity_file in solidity_files:
    print(f'Analyzing file: {solidity_file}')
    vulnerabilities = analyze_file(solidity_file)
    if vulnerabilities:
        report[solidity_file] = vulnerabilities

# Generar el reporte y crear la prueba
test_results = ""
if report:
    print("Vulnerabilities detected:")
    for filepath, vulnerabilities in report.items():
        print(f'\nFile: {filepath}')
        for name, line_number, line in vulnerabilities:
            print(f'  Vulnerability: {name}')
            print(f'    Line: {line_number}')
            print(f'    Code: {line}')
            try:
                test_results += create_and_run_fuzz_test(vulnerabilities, test_directory, show_output_in_terminal)
            except Exception as e:
                print(f"Failed to run fuzz test: {e}")
else:
    print("No vulnerabilities found.")

# Guardar el reporte en un archivo
with open('vulnerability_report.txt', 'w') as report_file:
    if report:
        report_file.write("Vulnerabilities detected:\n")
        for filepath, vulnerabilities in report.items():
            report_file.write(f'\nFile: {filepath}\n')
            for name, line_number, line in vulnerabilities:
                report_file.write(f'  Vulnerability: {name}\n')
                report_file.write(f'    Line: {line_number}\n')
                report_file.write(f'    Code: {line}\n')
        if not show_output_in_terminal:
            report_file.write("\nTest results:\n")
            report_file.write(test_results)
    else:
        report_file.write("No vulnerabilities found.\n")

print("\nThe report has been saved to 'vulnerability_report.txt'.")
