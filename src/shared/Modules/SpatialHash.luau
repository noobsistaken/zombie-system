-- Author: noobs

local SpatialHash = {}
SpatialHash.__index = SpatialHash

export type Entity = {
    Position: Vector3,
    [string]: any,
}

type GridData = {
    CellSize: number,
    Cells: { [number]: { [number]: { Entity } } },
}

export type SpatialHashGrid = typeof(setmetatable({} :: GridData, SpatialHash))

function SpatialHash.new(cellSize: number?): SpatialHashGrid
    local cells: { [number]: { [number]: { Entity } } } = {}
    return setmetatable({
        CellSize = cellSize or 10,
        Cells = cells,
    }, SpatialHash)
end

function SpatialHash.Clear(self: SpatialHashGrid)
    table.clear(self.Cells)
end

function SpatialHash.Insert(self: SpatialHashGrid, entity: Entity)
    local x = math.floor(entity.Position.X / self.CellSize)
    local z = math.floor(entity.Position.Z / self.CellSize)
    local column = self.Cells[x]
    if not column then
        column = {}
        self.Cells[x] = column
    end

    local cell = column[z]
    if not cell then
        cell = {}
        column[z] = cell
    end

    table.insert(cell, entity)
end

@native
function SpatialHash.GetNearby(self: SpatialHashGrid, position: Vector3, buffer: { Entity }?): { Entity }
    local result: { Entity } = buffer or {}
    table.clear(result)
    local cellSize = self.CellSize

    local cx = math.floor(position.X / cellSize)
    local cz = math.floor(position.Z / cellSize)

    for dx = -1, 1 do
        local column = self.Cells[cx + dx]
        if not column then
            continue
        end
        for dz = -1, 1 do
            local cell = column[cz + dz]
            if cell then
                for _, entity in cell do
                    table.insert(result, entity)
                end
            end
        end
    end

    return result
end

function SpatialHash.Rebuild(self: SpatialHashGrid, entities: { Entity })
    self:Clear()
    for _, entity in entities do
        self:Insert(entity)
    end
end

return SpatialHash
