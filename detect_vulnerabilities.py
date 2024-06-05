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

# Regex para detectar una división antes de una multiplicación
vulnerability_patterns = {
    "division_before_multiplication": re.compile(r'(/.*\*|\*/)', re.DOTALL),
}

# Función para analizar un archivo Solidity en busca de vulnerabilidades
def analyze_file(filepath):
    vulnerabilities = []
    with open(filepath, 'r') as file:
        code = file.read()
        for name, pattern in vulnerability_patterns.items():
            matches = pattern.findall(code)
            if matches:
                for match in matches:
                    start_index = code.find(match)
                    func_start = code.rfind('function ', 0, start_index)
                    func_end = code.find('}', start_index) + 1
                    function_code = code[func_start:func_end]
                    vulnerabilities.append((name, function_code, match))
    return vulnerabilities

# Función para crear y ejecutar una prueba de fuzzing con Foundry
def create_and_run_fuzz_test(vulnerabilities, test_dir, compilers):
    test_code_template = """
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import {Test, console} from "forge-std/Test.sol";

contract VulnerabilityTest is Test {
    function testfuzzTestVulnerability(uint256 a, uint256 b) public {
        uint256 boundedA = bound(a, 1, type(uint128).max);  // Asegurar que a esté en un rango seguro
        uint256 boundedB = bound(b, 1, type(uint128).max);  // Asegurar que b esté en un rango seguro y no sea cero
        
        // Realizar la operación vulnerable
        uint256 result = (boundedA / boundedB) * 10;

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

    # Intentar compilar y ejecutar la prueba con diferentes versiones del compilador
    for compiler in compilers:
        print(f"Trying compiler version {compiler}...")
        result = subprocess.run(["forge", "test", "--compiler-version", compiler, "--mc", "testVulnerabilityTest", "--mt", "fuzzTestVulnerability", "-vvvv"], capture_output=True, text=True)
        if result.returncode == 0:
            return result.stdout
        else:
            print(f"Compiler version {compiler} failed. Error:\n{result.stderr}")

    raise Exception("All compiler versions failed.")

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

# Lista de versiones de compiladores a intentar
compilers = ["0.8.25", "0.8.20", "0.8.17"]

# Generar el reporte y crear la prueba
test_results = ""
if report:
    print("Vulnerabilidades detectadas:")
    for filepath, vulnerabilities in report.items():
        print(f'\nArchivo: {filepath}')
        for name, function_code, match in vulnerabilities:
            print(f'  Vulnerabilidad: {name}')
            print(f'    Coincidencia: {match}')
            print(f'    Función completa:\n{function_code}')
            try:
                test_results += create_and_run_fuzz_test(vulnerabilities, test_directory, compilers)
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
            for name, function_code, match in vulnerabilities:
                report_file.write(f'  Vulnerabilidad: {name}\n')
                report_file.write(f'    Coincidencia: {match}\n')
                report_file.write(f'    Función completa:\n{function_code}\n')
        report_file.write("\nResultados de las pruebas:\n")
        report_file.write(test_results)
    else:
        report_file.write("No se encontraron vulnerabilidades.\n")

print("\nEl reporte ha sido guardado en 'vulnerability_report.txt'.")
