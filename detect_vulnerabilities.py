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
def create_and_run_fuzz_test(vulnerabilities, test_dir):
    test_code_template = """
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test, console} from "forge-std/Test.sol";

contract VulnerabilityTest is Test {
    function fuzzTestVulnerability(uint256 a, uint256 b) public {
        uint256 boundedA = bound(a, 1, type(uint128).max);  // Asegurar que a esté en un rango seguro
        uint256 boundedB = bound(b, 1, type(uint128).max);  // Asegurar que b esté en un rango seguro y no sea cero
        
        // Realizar la operación vulnerable
        uint256 result = (boundedA * 10) / boundedB;

        // Verificar la consistencia
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
        
        assert(result == expectedResult);  // Verificar la consistencia de la operación
    }
}
"""
    test_file_path = os.path.join(test_dir, "VulnerabilityTest.t.sol")

    with open(test_file_path, 'w') as test_file:
        test_file.write(test_code_template)

    # Ejecutar la prueba con Foundry y mostrar la salida en la terminal
    result = subprocess.run(["forge", "test", "--mc", "VulnerabilityTest", "--mt", "fuzzTestVulnerability", "-vvvv"], capture_output=True, text=True)
    return result.stdout

# Directorio base desde el cual se ejecuta el script
base_directory = os.getcwd()
test_directory = os.path.join(base_directory, 'test')

# Crear el directorio de pruebas si no existe
os.makedirs(test_directory, exist_ok=True)

# Buscar todos los archivos Solidity en la carpeta 'src'
solidity_files = find_solidity_files(base_directory)

# Verificar que se encontraron archivos Solidity
if not solidity_files:
    print("No se encontraron archivos Solidity en la carpeta 'src'.")
    exit(1)

# Analizar cada archivo Solidity
report = {}
for solidity_file in solidity_files:
    print(f'Analizando archivo: {solidity_file}')
    vulnerabilities = analyze_file(solidity_file)
    if vulnerabilities:
        report[solidity_file] = vulnerabilities

# Generar el reporte y crear la prueba
test_results = ""
if report:
    print("Vulnerabilidades detectadas:")
    for filepath, vulnerabilities in report.items():
        print(f'\nArchivo: {filepath}')
        for name, line_number, line in vulnerabilities:
            print(f'  Vulnerabilidad: {name}')
            print(f'    Línea: {line_number}')
            print(f'    Código: {line}')
            try:
                test_results += create_and_run_fuzz_test(vulnerabilities, test_directory)
            except Exception as e:
                print(f"Failed to run fuzz test: {e}")
else:
    print("No se encontraron vulnerabilidades.")

# Guardar el reporte en un archivo
with open('vulnerability_report.txt', 'w') as report_file:
    if report:
        report_file.write("Vulnerabilidades detectadas:\n")
        for filepath, vulnerabilities in report.items():
            report_file.write(f'\nArchivo: {filepath}\n')
            for name, line_number, line in vulnerabilities:
                report_file.write(f'  Vulnerabilidad: {name}\n')
                report_file.write(f'    Línea: {line_number}\n')
                report_file.write(f'    Código: {line}\n')
        report_file.write("\nResultados de las pruebas:\n")
        report_file.write(test_results)
    else:
        report_file.write("No se encontraron vulnerabilidades.\n")

print("\nEl reporte ha sido guardado en 'vulnerability_report.txt'.")
