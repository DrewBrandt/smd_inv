import pyperclip


def normalize_value(value: str) -> str:
    return value.strip().lower().replace(" ", "")


def normalize_package(package: str) -> str:
    value = package.strip().upper().replace(" ", "")
    return value or "0603"


def format_part_number(value: str, package: str) -> str:
    return f"RESISTOR-{package}-{value.upper()}"


def format_description(value: str, package: str) -> str:
    return f"Resistor {value} {package}"


def build_row(value: str, package: str, quantity: str) -> str:
    return "\t".join([
        "TRUE",
        "",
        format_part_number(value, package),
        "resistor",
        value,
        package,
        format_description(value, package),
        quantity,
        "Book",
        "",
        ""
    ])


def main():
    print("Enter resistor rows. Press Enter on resistor value to quit.\n")

    all_rows = []

    while True:
        value_in = input("Resistor value (example: 10k, 4k7, 220): ").strip()
        if not value_in:
            break

        value = normalize_value(value_in)
        package = normalize_package(
            input("Package (optional, default 0603): ").strip()
        )
        quantity = input("Quantity: ").strip()

        row = build_row(value, package, quantity)
        all_rows.append(row)

        pyperclip.copy("\n".join(all_rows))

        print("\nAdded row:")
        print(row)
        print("\nCopied all rows to clipboard.\n")

    print("\nFinal output:\n")
    print("\n".join(all_rows))

if __name__ == "__main__":
    main()
