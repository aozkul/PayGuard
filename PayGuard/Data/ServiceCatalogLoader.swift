//
//  ServiceCatalogLoader.swift
//  PayGuard
//
//  Created by Ali Ozkul on 01.05.26.
//

import Foundation

enum ServiceCatalogLoader {
    static func loadTemplates() -> [ServiceTemplate] {
        guard let url = Bundle.main.url(forResource: "ServiceCatalog", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let templates = try? JSONDecoder().decode([ServiceTemplate].self, from: data) else {
            return []
        }
        return templates
    }
}
